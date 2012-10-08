function [ev] = NlxLoadEV(varargin)
% NlxLoadEV: parses digital TTL pulses and event strings from a .nev file
%
%  ev = NlxLoadEV(filename, [name/value pairs]);
%
% Inputs: * = required, -> indicates default
%   filename - path to '*.nev' file
%   'TimeUnits' - Time units for output: ->'seconds', 'microseconds'
%   'FindPulses' - Parse TTL codes to generate a list of pulse start/end
%       times for each channel. (default true)
%
% Outputs: (For an events file file with 16 digital inputs and m events)
%  ev, a struct with the following fields,
%    'times' - m x 1 vector containing times of each event 
%    'ttls' - m x 16 vector of logicals (true/false) containing the new
%        state of each digital input at each event time
%    'pulses' - 1 x 16 cell array of pulse start and end times for each
%        digital input channel (m x 2 array)
%    'strings' - the text string associated with each event (m x 1 cell
%        array of strings)
%    'timeunits' - the units of all event times (usually 'seconds')
%    'info' - a struct with event file headers and NlxLoadEV arguments
%
%
% Example: Get the pulse times from channel 15 of nevents.nev
%  cd C:\path\to\data
%  ev = NlxLoadEV('nevents.nev')
%  laserpulses = ev.pulses{15};
%
% See the 'NOTES' section in the code for additional discussion.

% Tom Davidson <tjd@stanford.edu> April 2010

% NOTES:
%
%  -An event is generated by Cheetah any time a TTL channel goes high or
%   low. The time of the change is recorded in the timestamp, and the
%   identity of the channel (or channels) that have changed is encoded in a
%   bitfield representing the new state of all the digital inputs after the
%   change. There are 16 TTL channels, so the state of the digital inputs
%   is stored in the .nev file as a 16 bit-wide bitfield. Nlx2MatEV treats
%   this bitfield as an unsigned binary integer (range 0-65536) and returns
%   the decimal equivalent as a double-precision float with (so if bit 5
%   were to go high, and all the other bits are low, an event would be
%   generated with a nTTLs value of 32.0). In this function, we convert the
%   nTTL field back into an m x 16 array of logical values. 
%
%  -If 'FindPulses' is true, we also create a per-channel list of start/end
%   times for each TTL channel going high.
%
%  -events can also be generated manually by the user, or by sending NetCom
%   commands over the network, or by the use of external digital IO cards.
%   These do not change the nTTL field, and are not currently supported by
%   this wrapper function.
%
%  -eventID is always 0 for TTL pulses on Digital Lynx, so we ignore it for
%   now
%
%  -eventstring is redundant for TTL pulses, e.g. 'Digital Lynx Parallel
%   Input Port TTL (0x4000)', so we ignore it for now
%
%  -extras never contains anything other than zeros, so we ignore it for
%   now
%
%  -Timestamps are stored as unsigned 64-bit integers (uint64) in the
%   original file, but returned as double-precision floats. There's no
%   reason to convert from 'double' back to 'uint64', though, since the
%   memory requirements are the same, and the floating point precision
%   (given by 'eps) is << 1 (i.e. is accurate to the microsecond) even for
%   very large timestamp values (corresponding to years-long recordings).

% TODO:
%  -support sample#/time ranges
%  -figure out/handle what cheetah does if TTLs are high at start of acq
%  -handle eventstrings/manual events if people want them
%  -'InvertTTL' per channel?

%% check dependencies

CheckForNlx2Mat('EV');

%% set up function input arguments
p = inputParser;
p.addRequired('Filename', @sub_isfile); 
p.addParamValue('TimeUnits', 'seconds', @(s)sub_isinlist(s,{'seconds', 'microseconds'}));
p.addParamValue('FindPulses', true, @islogical);
p.parse(varargin{:});

% parse arguments to arglist
a = p.Results;

% Neuralynx bug: can't see files containing the '~' character, needs that
% part of path to be in '/home/user' format
if a.Filename(1) == '~',
  oldwd = pwd;
  cd ('~');
  a.Filename(1) = [];
  a.Filename = [pwd '/' a.Filename];
  cd (oldwd)
end


%% constants


%% set up extraction parameters
FieldSelection = [1 0 1 0 1]; % [timestamps eventID TTLs extras evstring]
ExtractHeader = 1;
ExtractMode = 1; % 1-all, 2-range, 3-list, 4-timestamp range, 5-ts list
ModeArray = []; % blank for mode 1 (all)
% 2 elements for range (mode 2 or 4); n elements for list (mode 3 or 5)
% indexes (mode 2 or 3) are zero-indexed

%% run requested extraction
[ev.times nTTLs ev.strings ev.info.rawheader] = Nlx2MatEV(a.Filename, FieldSelection, ExtractHeader, ExtractMode, ModeArray);


%% parse header and calculate some useful values

ev.info.header = NlxParseHeader(ev.info.rawheader);


%% convert datatypes and scale as requested

% handle case of bit16 being reported as -32768 by Nlx2MatEV
nTTLs(nTTLs==-32768) = 32768;

% convert evids to uint16
ttls_uint16 = uint16(nTTLs);

% convert uint16 to array of logicals
ev.ttls = false(16, size(ttls_uint16,2)); % preallocate array
for j = 1:16,
    ev.ttls(j,:) = bitget(ttls_uint16,j);
end


% convert times to seconds if requested
switch a.TimeUnits
    case 'seconds'
        ev.times = ev.times ./ 1e6;
    case 'microseconds'
        % no convert
    otherwise
        error('bad TimeUnits');            
end
ev.timeunits = a.TimeUnits;

%% find start/end times of pulses for each TTL channel

if a.FindPulses

    % Note that the state of a single channel can stay the same across
    % multiple events, so we have to look for changes in our channel's
    % state     
    
    % Each event issued gives the end time of the previous TTL state, as
    % well as the start time of the new TTL state. Double them up to make
    % this explicit.
    
    %time_startend = zeros(1, 2 * size(ev.times,2)); %pre-allocate array
    time_startend = zeros(2, size(ev.times,2)); %pre-allocate array

    % TTL state start times
    time_startend(1,:) = ev.times; 

    % each TTL state ends at next start time
    time_startend(2,:) = ev.times([2:end end]); % last end repeated
    
    for j = 1:16,
        
        % skip processing if no pulses
        if ~any(ev.ttls(j,:)), ev.pulses{j} = []; continue; end;
       
        % assign TTL state to match start/end times calculated above
        ttlj_startend = repmat(ev.ttls(j,:),[2 1]);
        
        ev.pulses{j} = sub_logical2seg(time_startend, ttlj_startend(:));
    end    
end


%% clean up and return

% save a copy of arguments to this function
ev.info.loadargs = a;

% order struct fields alphabetically
ev = orderfields(ev);

% transpose arrays for consistency:
ev.times = ev.times';
ev.ttls = ev.ttls';

%% Subfunctions
function tf = sub_isfile(s)
if exist(s, 'file')~=2
    error('Must be a valid file.');
end
tf = true;


function tf = sub_isinlist(s, validlist)
if ~any(strcmpi(s, validlist))
    error(['Value ''' s ''' not in valid list ' cell2str(validlist)]);
end
tf = true;


function seg = sub_logical2seg( t, l)
%LOGICAL2SEG create segments from a logical array
%
%  seg=LOGICAL2SEG(x,v) given a vector of indices or a logical index
%  vector v, this function will return segments in x defined by those
%  indices.
%

%  Copyright 2005-2008 Fabian Kloosterman, fkloos@mit.edu

if nargin<1
  help(mfilename)
  return
end

if nargin<2
  l = t;
  t = 1:numel(l);
end

if numel(l) == numel(t)
  %l is an logical vector
  l = find( l );
else
  %l is an index vector
end

l = l(:);

if isempty(l)
    seg = zeros(0,2);
    return
end;

segstart = l([1 ; 1+find( diff(l)>1 )]);
segend = l([find( diff(l)>1 ) ; numel(l)]);

%b = burstdetect( l, 'MinISI', 1, 'MaxISI', 1 );

%segstart = t( l(b==1) );
%segend = t( l(b==3) );


seg = t([ segstart(:) segend(:)]);

