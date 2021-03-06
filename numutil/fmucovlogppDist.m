function [D]=fmucovlogppDist(X, Z, dim, order, ridge, VERB)
if ( nargin < 2 ) Z = []; end
if ( nargin < 3 || isempty(dim) ) dim=[]; end; % dimension which contains the examples
if ( nargin < 4 || isempty(order) ) order=[]; end;
if ( nargin < 5 || isempty(ridge) ) ridge=[]; end;
if ( nargin < 6 || isempty(VERB) ) VERB=[]; end;
D=covlogppDist(X,Z,dim,order,ridge,VERB);
D=mean(D,ndims(D));
return;