function [outName] = ampAccel01( vidFile, alpha, outDir, varargin)
    %% Read Video
    vr = VideoReader(vidFile);
    [~, writeTag, ~] = fileparts(vidFile);
    FrameRate = vr.FrameRate;    
    frame = vr.read(1);
    [h,w,nC] = size(frame);
    nF = vr.NumberOfFrames;
    
    %% Parse Input
    p = inputParser();

    defaultAttenuateOtherFrequencies = false; %If true, use reference frame phases
    pyrTypes = {'octave','octave2', 'halfOctave', 'smoothHalfOctave', 'quarterOctave'}; 
    checkPyrType = @(x) find(ismember(x, pyrTypes));
    defaultPyrType = 'octave2';
    defaultSigma = 0;
    defaultTemporalFilter = @FIRWindowBP;
    defaultScale = 1;
    defaultFrames = [1, nF];
    
    addOptional(p, 'attenuateOtherFreq', defaultAttenuateOtherFrequencies, @islogical);
    addOptional(p, 'pyrType', defaultPyrType, checkPyrType);
    addOptional(p,'sigma', defaultSigma, @isnumeric);   
    addOptional(p, 'temporalFilter', defaultTemporalFilter);
    addOptional(p, 'scaleVideo', defaultScale);
    addOptional(p, 'useFrames', defaultFrames);
    
    parse(p, varargin{:});

    refFrame = 1;
    attenuateOtherFreq = p.Results.attenuateOtherFreq;
    pyrType            = p.Results.pyrType;
    sigma              = p.Results.sigma;
    temporalFilter     = p.Results.temporalFilter;
    scaleVideo         = p.Results.scaleVideo;
    frames             = p.Results.useFrames;

    %% Compute spatial filters        
    
    fprintf('Computing spatial filters\n');
    ht = maxSCFpyrHt(zeros(h,w));
    switch pyrType
        case 'octave2'
            filters = getFilters([h w], 2.^[0:-1:-ht], 2);
            repString = 'octave';
            fprintf('Using two orientation octave bandwidth pyramid\n');              
        case 'octave'
            filters = getFilters([h w], 2.^[0:-1:-ht], 4);
            repString = 'octave';
            fprintf('Using octave bandwidth pyramid\n');  
        case 'halfOctave'            
            filters = getFilters([h w], 2.^[0:-0.5:-ht], 8,'twidth', 0.75);
            repString = 'halfOctave';
            fprintf('Using half octave bandwidth pyramid\n'); 
        case 'smoothHalfOctave'
            filters = getFiltersSmoothWindow([h w], 2, 'filtersPerOctave', 2);           
            repString = 'smoothHalfOctave';
            fprintf('Using half octave pyramid with smooth window.\n');
        case 'quarterOctave'
            filters = getFiltersSmoothWindow([h w], 2, 'filtersPerOctave', 4);
            repString = 'quarterOctave';
            fprintf('Using quarter octave pyramid.\n');
        otherwise 
            error('Invalid Filter Types');
    end

    [croppedFilters, filtIDX] = getFilterIDX(filters);
 %% Initialization of motion magnified luma component
    magnifiedLumaFFT = zeros(h,w,nF,'single');
    
    buildLevel = @(im_dft, k) ifft2(ifftshift(croppedFilters{k}.* ...
        im_dft(filtIDX{k,1}, filtIDX{k,2})));
    
    reconLevel = @(im_dft, k) 2*(croppedFilters{k}.*fftshift(fft2(im_dft)));


    %% First compute phase differences from reference frame
    numLevels = numel(filters);        
    fprintf('Moving video to Fourier domain\n');
    vidFFT = zeros(h,w,nF,'single');
    for k = 1:nF
        originalFrame = rgb2ntsc(im2single(vid(:,:,:,k)));
        tVid = imresize(originalFrame(:,:,1), [h w]);
        vidFFT(:,:,k) = single(fftshift(fft2(tVid)));
    end
    clear vid;

    for level = 2:numLevels-1
        %% Compute phases of level
        % We assume that the video is mostly static
        pyrRef = buildLevel(vidFFT(:,:,refFrame), level);        
        pyrRefPhaseOrig = pyrRef./abs(pyrRef);
        pyrRef = angle(pyrRef);        
                    pyrPrev = zeros(size(pyrRef));
        delta = zeros(size(pyrRef,1), size(pyrRef,2) ,nF,'single');
        fprintf('Processing level %d of %d\n', level, numLevels);
        delta(:,:,1) = pyrPrev;
        for frameIDX = 2:nF
            filterResponse = buildLevel(vidFFT(:,:,frameIDX), level);
            pyrCurrent = angle(filterResponse);
            delta(:,:,frameIDX) = single(mod(pi+pyrCurrent-pyrPrev,2*pi)-pi);        
          %  delta2(:,:,frameIDX) = single(mod(pi+pyrCurrent-pyrRef,2*pi)-pi);        
            pyrPrev = pyrCurrent;            
        end
        
        % Cumulative sum (phase unwrapping)
        delta = cumsum(delta,3); 
        
        %% Temporal Filtering
        fprintf('Bandpassing phases\n');
        delta = temporalFilter(delta, fl/fs,fh/fs); 


        %% Apply magnification

        fprintf('Applying magnification\n');
        for frameIDX = 1:nF

            phaseOfFrame = delta(:,:,frameIDX);
            originalLevel = buildLevel(vidFFT(:,:,frameIDX),level);
            %% Amplitude Weighted Blur        
            if (sigma~= 0)
                phaseOfFrame = AmplitudeWeightedBlur(phaseOfFrame, abs(originalLevel)+eps, sigma);        
            end

            % Increase phase variation
            phaseOfFrame = magPhase *phaseOfFrame;  
            
            if (attenuateOtherFreq)
                tempOrig = abs(originalLevel).*pyrRefPhaseOrig;
            else
                tempOrig = originalLevel;
            end
            tempTransformOut = exp(1i*phaseOfFrame).*tempOrig; 

            curLevelFrame = reconLevel(tempTransformOut, level);
            magnifiedLumaFFT(filtIDX{level,1}, filtIDX{level,2},frameIDX) = curLevelFrame + magnifiedLumaFFT(filtIDX{level,1}, filtIDX{level,2},frameIDX);
        end



    end
    %% Add unmolested lowpass residual
    level = numel(filters);
    for frameIDX = 1:nF 
        lowpassFrame = vidFFT(filtIDX{level,1},filtIDX{level,2},frameIDX).*croppedFilters{end}.^2;
        magnifiedLumaFFT(filtIDX{level,1},filtIDX{level,2},frameIDX) = magnifiedLumaFFT(filtIDX{level,1},filtIDX{level,2},frameIDX) + lowpassFrame;    
    end
    clear vidFFT;
    vr = VideoReader(vidFile);
    vid = vr.read([frames]);
    res = zeros(h,w,nC,nF,'uint8');
    for k = 1:nF
        magnifiedLuma = real(ifft2(ifftshift(magnifiedLumaFFT(:,:,k))));
        outFrame(:,:,1) = magnifiedLuma;
        originalFrame = rgb2ntsc(im2single(vid(:,:,:,k)));    
        originalFrame = imresize(originalFrame, [h, w]);
        outFrame(:,:,2:3) = originalFrame(:,:,2:3);
        outFrame = ntsc2rgb(outFrame);        
        %% Put frame in output
        res(:,:,:,k) = im2uint8(outFrame);
    end

    outName = sprintf('%s-%s-band%0.2f-%0.2f-sr%d-alpha%d-mp%d-sigma%d-scale%0.2f-frames%d-%d-%s-2orientCSP.avi', writeTag, func2str(temporalFilter), fl, fh,fs, magPhase, attenuateOtherFreq, sigma, scaleVideo, frames(1), frames(2), repString);
    writeVideo(res, FrameRate, fullfile(outDir, outName));   
    combName = ['comb' outName];
    writeVideo(cat(2,vid,res), FrameRate, fullfile(outDir, combName));
    
 
    
end
