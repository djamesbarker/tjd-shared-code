function p = td_sharedcode_setup.m
% LOCAL_PATHDEF - some paths you might want - Tom's SVN repo
%
% In your startup.m (or at the command line)
%
% run('path/to/this/file/td_sharedcode_setup.m');
%
% This adds directories in Tom's shared code repository to your path

 
path_to_repo = pwd; % since we cd'd here before running this

p = [...
    path_to_repo '/matlab:', ...
    path_to_repo '/matlab/import:', ...
    path_to_repo '/matlab/util:', ...
    path_to_repo '/matlab/obj:', ...
    path_to_repo '/matlab/obj/filt:', ...
    path_to_repo '/matlab/obj/defs:', ...
    ...
];

% add Tom's code to the beginning of the path
path(p, path);