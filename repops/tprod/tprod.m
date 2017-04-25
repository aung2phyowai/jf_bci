function [varargout]=tprod(varargin)
% Multi-dimensional generalisation of matrix multiplication
%
% function [Z]=tprod(X,xdimspec,Y,ydimspec[,optStr,blksz])
%
% This function computes a generalised multi-dimensional matrix product
% based upon the Einstein Summation Convention (ESC).  This means
% given 2 n-d inputs:
%   X = [ A x B x C x E .... ], denoted in ESC as X_{abce}
%   Y = [ D x F x G x H .... ], denoted in ESC as Y_{dfgh}
% we define a particular tensor operation producing the result Z as
%  Z_{cedf} = X_{abce}Y_{dfab}
% where, we form an inner-product (multiply+sum) for the dimensions with
% *matching* labels on the Right Hand Side (RHS) and an outer-product over
% the remaining dimensions.  Note, that in conventional ESC the *order* of
% dimensions in Z is specified on the LHS where the matching label specifies
% its location.
% 
% Tprod calls closely follow this convention, the tprod equivalent of the
% above is[1]:
%  Z = tprod(X,[-1 -2 1 2],Y,[3 4 -1 -2])
% here, *matching negatively* labelled RHS dimensions are inner-product
% dimensionss, whilst the *positively* labelled dimensions directly
% specify the position of that dimension in the result Z. Hence only 2
% dimension-specifications are needed to unambigiously specify this
% tensor product.  
%
% [1] Note: if you find this syntax to difficult the ETPROD wrapper function
% is provided to directly make calls in ESC syntax, e.g.
%    Z = etprod('cedf',X,'abce',Y,'dfab');
%
% It is perhaps easiest to understand the calling syntax with some simple
% examples: 
%
% 1-d cases
%   X = randn(100,1);             % make 100 1-d data points
%   Z = tprod(X,1,X,1);           % element-wise multiply, =X.*X
%   Z = tprod(X,1,X,2);           % outer-product = X*X'
%   Z = tprod(X,-1,X,-1);         % inner product = X'*X
%
% 2-d statistical examples
%   X=randn(10,100);              % 10d points x 100 trials
%   Z=tprod(X,[-1 2],X,[-1 2]);   % squared norm of each trial, =sum(X.*X)
%   Z=tprod(X,[1 -2],X,[2 -2]);   % covariance over trials,     =X*X'
%
% More complex 3-d cases
%   X = randn(10,20,100);          % dim x samples x trials set of timeseries
%   sf= randn(10,1);               % dim x 1 spatial filter
%   tf= randn(20,1);               % samples x 1 temporal filter
%
%   % spatially filter Z -> [1 x samp x trials ]
%   Z=tprod(X,[-1 2 3],sf,[-1 1]);
%   % MATLAB equivalent: reshape(reshape(X,[10,20*100])*sf,[1 20 100])
%
%   % temporaly fitler Z -> [dim x 1 x trials ]
%   Z=tprod(X,[1 -2 3],tf,[-2 2]); 
%   % MATLAB equivalent: for i=1:size(X,3); Z(:,:,i)=X(:,:,i)*tf; end;
%   
%   % OP over dim, IP over samples, sequ over trial = per trial covariance
%   Z=tprod(X,[1 -2 3],X,[2 -2 3])/size(X,3); 
%   % MATLAB equivalent: for i=1:size(X,3); Z(:,:,i)=X(:,:,i)*X(:,:,i)'./size(X,3); end;
%
% n-d cases
%
%  X = randn(10,9,8,7,6);
%  Z = tprod(X,[1 2 -3 -4 3],X,[1 2 -3 -4 3]); % accumulate away dimensions 3&4 and squeeze the result to 3d
%  % MATLAB equivalent; for i=1:size(X,5); Xi=reshape(X(:,:,:,:,i),[10*9 8*7]); Z(:,:,i) = reshape(sum(Xi.*Xi,2),[10 9]); end;
%
% INPUTS:
%  X        - n-d double/single matrix
%
%  xdimspec - signed label for each X dimension. Interperted as:
%              1) 0 labels must come from singlenton dims and means they are
%              squeezed out of the input.
%              2) NEGATIVE labels must come in matched pairs in both X and Y 
%                 and denote inner-product dimensions
%              3) POSITIVE labels denote the position of this dimension in
%              the output matrix Z.  Positive labels must be unique in X.
%              Depending on whether the same label occurs in Y 2 conditions
%              can occur:
%                a) X label has NO match in Y.  Then this is an
%                outer-product dimension.  
%                b) X label matches a label in Y. Then this dimension is an
%                aligned in both X and Y, such that they increment together
%                -- as if there was an outer loop over these dims indicies
%
%  Y        - m-d double/single matrix, 
%             N.B. if Y==[], then it is assumed to be a copy of X.
%
%  ydimspec - signed label for each Y dimension.  If not given yaccdim
%             defaults to -(1:# negative labels in (xdimspec)) followed by
%             enough positive lables to put the remaining dims after the X
%             dims in the output. (so it accumlates the first dims and
%             outer-prods the rest)
%
%  optStr  - String of single character control options,
%            'm'= don't use the, fast but perhaps not memory efficient,
%                 MATLAB code when possible. 
%            'n'=use the *new* calling convention: tprod(X,xdimspec,Y,ydimspec)
%            'o'=use the *old* calling convention: tprod(X,Y,xdimspec,ydimspec)
%  blksz    - Internally tprod computes the results in blocks of blksz size in 
%             order to keep information efficiently in the cache.  TPROD 
%             defaults this size to a size of 16, i.e. 16x16 blocks of doubles.
%             On different machines (with different cache sizes) tweaking this
%             parameter may result some speedups.
% 
% OUTPUT:
%  Z       - n-d double matrix with the size given by the sizes of the
%            POSITIVE labels in xdimspec/ydimspec
%
% See Also:  tprod_testcases, etprod
%
% Class support of input:
%     float: double, single
% 
% 
% Copyright 2006-     by Jason D.R. Farquhar (jdrf@zepler.org)

% Permission is granted for anyone to copy, use, or modify this
% software and accompanying documents for any uncommercial
% purposes, provided this copyright notice is retained, and note is
% made of any changes that have been made. This software and
% documents are distributed without any warranty, express or
% implied

persistent compileOK;
mlock % weirdly this is needed for the persistent variable to remain set between calls

% only try to compile the function once
if ( isempty(compileOK) )
  if ( exist(fullfile(fileparts(mfilename('fullpath')),'compileFailed'),'file') ) % if it's there stop
    % mark as bad and use the fall-back code
    compileOK=false;
    [varargout{1:max(1,nargout)}] = tprodm(varargin{:}); 
    return;
  end
  % mark as failed, remove on success
  compileOK=false;
  fid=fopen(fullfile(fileparts(mfilename('fullpath')),'compileFailed'),'w');fprintf(fid,'1');fclose(fid);
  % The rest of this code is a mex-hiding mechanism which compilies the mex if
  % this runs and recursivly calls itself.  
  % Based upon code from: http://theoval.sys.uea.ac.uk/matlab
  cwd  = pwd; % store the current working directory
  name = mfilename('fullpath'); % get the directory where we are
                                % find out what directory it is defined in
  name(name=='\')='/';
  if(isequal(name(end-1:end),'.m')) name=name(1:end-2); end;
  dir=name(1:max(find(name == '/')-1));
  try % try changing to that directory
    cd(dir);
  catch   % this should never happen, but just in case!
    cd(cwd);
    error(['unable to locate directory containing ''' name '.m''']);
  end
  cfiles={'ddtprod.c','dstprod.c','sdtprod.c','sstprod.c','tprod_util.c','tprod_mex.c','mxInfo.c','mxInfo_mex.c'};
  try % try recompiling the MEX file
    fprintf(['Compiling ' mfilename ' for first use\n']);
    if ( exist('OCTAVE_VERSION','builtin') ) 
      mkoctfile(cfiles{:},'-v','-mex','-o',mfilename);
    else
      mex(cfiles{:},'-O','-output',mfilename);
    end
    fprintf('done\n');
    compileOK=true;
    % remove the failed file
    delete(fullfile(mfilename('fullpath'),'compileFailed'))
    % if ( exist('OCTAVE_VERSION') ) % remove the .m file as it shaddows the .mex
	 % 	 movefile([mfilename '.m'],[mfilename '.m.bak']);
	 % end
  catch
    cd(cwd);
    warning(sprintf('unable to compile MEX version of ''%s'',\n, please make sure your MEX compilier is setup correctly\n(try ''mex -setup'')\nUsing fallback matlab implementation from now on!', name));
  end

  cd(cwd); % change back to the current working directory
  if ( compileOK )
    rehash;  % refresh the function and file system caches
  end
end

if ( compileOK ) % recursively invoke MEX version using the same input and output arguments
  [varargout{1:nargout}] = feval(mfilename, varargin{:});
else % use the fall-back code
  [varargout{1:nargout}] = tprodm(varargin{:}); 
end

% bye bye...
return;
