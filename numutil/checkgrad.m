function [d dy dh ddy ddh] = checkgrad(fFn, x, e, hesDiag, verb,varargin)
% [d dy dh ddy ddh] = checkgrad(fFn, x, e, hesDiag, verb, ....)
% checkgrad checks the derivatives in a function, by comparing them to finite
% differences approximations. The partial derivatives and the approximation
% are printed and the norm of the diffrence divided by the norm of the sum is
% returned as an indication of accuracy.
%
% Inputs:
%  fFn - function to return the feval and the derivatives of the form:
%             [y dy]=feval(fFn,x)
%  x   - [dx1] point about which to compute the perf
%  e   - [1x1] scaling for the change                                  (1e-3)
%  hesDiag - [bool] flag if we compute the diag-hessian estimate also (false)
%  verb - [int] verbosity level                                           (0)
%
% Outputs:
%  d  - [4x1] = [norm(dy-dh)/norm(dy)     norm(dy-dh)/norm(dy+dh) ...
%                norm(ddy-ddh)/norm(ddy)  norm(ddy-ddy)/norm(ddy+ddh)]
%                where dh = finite-diff approx grad/hess estimate,  dy=function grad/hess est
% N.B. for multi-dimensional outputs we assume:
%  dfdx = [ size(x) x size(f) ] 
%
if ( nargin < 3 || isempty(e) ) e=1e-3; end;
if ( nargin < 4 || isempty(hesDiag) ) hesDiag=false; end;
if ( nargin < 5 || isempty(verb) ) verb=0; end;
if ( hesDiag ) % get the partial derivatives dy
   if ( iscell(fFn) ) 
      [y dy ddy]=feval(fFn{1},x,fFn{2:end},varargin{:}); 
   else 
      [y dy ddy]=feval(fFn,x,varargin{:});  
   end;
else
   if ( iscell(fFn) ) 
      [y dy]=feval(fFn{1},x,fFn{2:end},varargin{:}); 
   else 
      [y dy]=feval(fFn,x,varargin{:});  
   end;
   ddy=zeros(size(x));
end
% shape to 2-d matrix of numel(x) x numel(f) == N.B. must have same #el as dy
dh =zeros(size(dy));
dh =reshape(dh,[prod(size(x)),prod(size(y))]); % grad is size(x) x size(y)
ddh=zeros(size(dh));
tx = x;
for j = 1:numel(x)
   if( verb>0 && j==ceil(round(100*j/numel(x))*numel(x)/100) ) fprintf('.');end
   tx(j) = x(j)+e;                               % perturb a single dimension
   if ( iscell(fFn) ) 
      y2=feval(fFn{1},tx,fFn{2:end},varargin{:}); 
   else 
      y2=feval(fFn,tx,varargin{:});  
   end;
   tx(j) = x(j)-e ;
   if ( iscell(fFn) ) 
      y1=feval(fFn{1},tx,fFn{2:end},varargin{:}); 
   else 
      y1=feval(fFn,tx,varargin{:});  
   end;
   tx(j) = x(j);                                 % reset it
   dh(j,:) = (y2(:) - y1(:))/(2*e);
   ddh(j,:)= (y2(:) - 2*y(:) + y1(:))/(e*e);     % diag hessian est
end
% reshape output to be the same as the one generated by the function
dh=reshape(dh,size(dy));
if ( hesDiag ) ddh=reshape(ddh,size(dy)); end;
fprintf('\n');
if (verb > 0 ) 
   fprintf('[dy(:) dh(:)] =\n');
   disp([dy(:) dh(:)])                                      % print the vectors
   if ( hesDiag )
	  if( isequal(size(ddy),size(ddh)) )
       fprintf('[ddy(:) ddh(:)] =\n'); disp([ddy(:) ddh(:)]);
	  else
		 fprintf('ddh(:) =\n'); disp(ddh(:));
	  end
   end;
end;
% return norm of diff divided by norm of sum
d=[norm(dh(:)-dy(:))/norm(dy(:)) corr(dh(:)./norm(dh(:)),dy(:)./norm(dy(:)))];
if ( hesDiag && isequal(size(ddy),size(ddh)) ) 
   d=[d norm(ddh(:)-ddy(:))/norm(ddy(:)) corr(ddy(:)./norm(ddy(:)),ddh(:)./norm(ddh(:)))]; 
end;
if( verb>=0 || nargout==0 ) 
   fprintf('dy: \t%0.6g \t%0.6g\n',d(1:2))
   if ( hesDiag && isequal(size(ddy),size(ddh)) ) 
      fprintf('ddy:\t%0.6g \t%0.6g\n',d(3:end)); 
   end
end;

