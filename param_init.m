if ~exist('done_init','var')    
    if isunix
        addpath(genpath('../lib'))
        DLIB= '/data/vision/billf/donglai-lib/VisionLib/Donglai/';
    end
    if ismac
        addpath(genpath('lib'))
        DLIB= '/Users/Stephen/Code/VisionLib/Donglai/';
    end
    addpath('util')
    
    addpath(genpath([DLIB 'Low/Flow/CeOF/']))
    addpath(genpath([DLIB 'Util']))
    addpath(genpath([DLIB 'Low/Flow/Deqing']));
    addpath('T_p2v')
    addpath('ICIP2015')
    addpath('P_amp')
    addpath('P_motion')
    addpath('P_pdic')
    addpath('T_flow')
    done_init=1;
    set(0,'DefaultFigureWindowStyle','docked')
end
