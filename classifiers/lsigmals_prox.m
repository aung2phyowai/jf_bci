function [wb,U,s,V] = proximalLsigmaLS(X,Y,C,varargin)
% proximal opt to solve the l1 reg least squares problem
%
% wb = proximalOpt(X,Y,C,varargin)
% 
%  J = \min_{W,b} |Tr(X*W)+b-y|^2 + C |W|_*
opts=struct('stepSize',[],'maxIter',5000,'verb',1,'wb',[],'alphab',[],...
            'objTol',1e-8,'objTol0',0,'tol',1e-6,'tol0',0,'marate',.1,...
            'lineSearchAccel',1,'lineSearchStep',1,'dim',[],'symDim',[],'lipzApprox','sphere');%[1 1.05 2]);
opts=parseOpts(opts,varargin);
if ( numel(opts.lineSearchStep)<3 ) opts.lineSearchStep(end+1:5)=1; end;
szX=size(X); X=reshape(X,[],size(X,ndims(X))); % get orginal size, then reshape into [feat x examples]

if ( ~isempty(opts.symDim) && size(X,opts.symDim(1))~=size(X,opts.symDim(2)) ) 
  error('symetric dims are not the same size!');
end

wb=opts.wb;
if ( isempty(wb) && ~isempty(opts.alphab) ) wb=opts.alphab; end;
if ( isempty(wb) ) wb=zeros(size(X,1)+1,1);  end
if (numel(wb)==size(X,1) ) wb=[wb(:);0]; end;
W=wb(1:end-1); b=wb(end);

rho=opts.stepSize; 
if( isempty(rho) ) % stepSize = Lipschiz constant = approx inv hessian
  % est of largest eigenvalue of the data covariance matrix
  sX=sum(X,2); N=size(X,2); 
  %H =X*X';
  % tic
  %   H=[X*X' sX;... % N.B. don't forget the factor of 2
  %      sX' N];
  %   w=[X(:,1);1]; l=sqrt(w'*w); for i=1:10; w=H*w/l; l=sqrt(w'*w); end; 
  % toc
  % tic
  %   XX=X*X';
  %   w=X(:,1);b=0; l=sqrt(w'*w+b*b); for i=1:10; w=(XX*w+sX*b)/l; b=(sX'*w+N*b);l=sqrt(w'*w+b*b); end; 
  % toc  
  tic
  w=X(:,1);b=1; 
  l=sqrt(w'*w); for i=1:10; w=(X*(w'*X)')/l;l=sqrt(w'*w); end; 
  w=w/l;
  toc
  rho=l*2.2; % N.B. Don't forget the factor of 2!
  %rho=2*max(abs(eig(H)));
  %rho=sqrt(X(:)'*X(:));  
end;
% diag-hessian approx for Lipsitch constants?
tic,H  =tprod(reshape(X,szX),[1 3 -3],[],[2 3 -3]);toc % d x d x t
tic,H1 =tprod(reshape(X,szX),[1 -2 -3],[],[2 -2 -3]);toc % d x d
if ( strcmp(opts.lipzApprox,'hess') )
  % diag-hessian approx for Lipsitch constants?
  H  =tprod(X,[1 3 -3],[],[2 3 -3]); % d x d x t
  ddL = [sum(X.*X,2);N];
  scale = (l./sqrt(sum((ddL(1:end-1).*w).^2)))*2.5;
  ddL = ddL*(l./sqrt(sum((ddL(1:end-1).*w).^2)))*2.5;
  lipW0 = ddL(1:end-1); lipb0=N; 
else
  lipW0 = rho;          lipb0=N;
end;

nFeat=[]; if ( C<0 ) nFeat=-C; C=0;  end;

lineSearchStep=opts.lineSearchStep(1);
J=inf; oW=zeros(size(W)); ob=b; ooW=oW; oob=b; oC=C; dw0=0;
if ( isequal(opts.symDim(:),[1;2]) )
  [U,s]  =eig(reshape(wb(1:end-1),szX(1:end-1))); V=U';  s=diag(s); 
else
  [U,s,V]=svd(reshape(wb(1:end-1),szX(1:end-1)),'econ'); s=diag(s);
end
os=s; step=1;
for iter=1:opts.maxIter;
  oJ=J; % prev objective
  
  ooW=oW; oob=ob; oW=W; ob=b; os=s; % N.B. save the solutions *after* the prox but before the acceleration step!!
  if( opts.lineSearchAccel && norm(oC-C)./max(1,norm(C))<.1 && iter>2 ) 
    if ( opts.verb>0 ) fprintf('a'); end;
    % N.B. Accel gradient method:
    %  y = x_{k-1} + (k-2)/(k+1)*(x_{k-1}-x_{k-2})
    % x_k= prox_rho(y-dL(y)/rho);
    dW= oW-ooW; db=ob-oob;% track the gradient bits,% x_k - x_{k-1)
    W = W + dW*(iter-1)/(iter+2)*lineSearchStep;
    b = b + db*(iter-1)/(iter+2)*lineSearchStep;
    if ( isequal(opts.symDim(:),[1;2]) ) % decompose this solution for obj computation
      [U,s]  =eig(reshape(W,szX(1:end-1))); V=U';  s=diag(s); 
    else
      [U,s,V]=svd(reshape(W,szX(1:end-1)),'econ'); s=diag(s);
    end
  end

  % eval current solution
  f  = (W'*X)';
  err= f-Y;
  R = sum(abs(s));
  L = err(:)'*err(:);
  dLW = 2*X*err; %tprod(X,[1:ndims(X)-1 -ndims(X)],err,[-ndims(X)]); % = X*X'*wb - X*y'
  dLb = 2*sum(err);
  dRW = sign(s);
  J = C*R + L ;

  % adapt step size
  if ( norm(oC-C)./max(1,norm(C))<.05 && (oC*R+L)>=oJ && J>=oJ ) %*(1+1e-3) ) 
    if ( opts.verb>0 ) fprintf('*'); end;
    if (  opts.lineSearchAccel ) 
      lineSearchStep=max(opts.lineSearchStep(4),min(opts.lineSearchStep(5),lineSearchStep/opts.lineSearchStep(3)));
    end;
    %rho=rho*1.5; 
  else
    if ( opts.lineSearchAccel ) 
      lineSearchStep=max(opts.lineSearchStep(4),min(opts.lineSearchStep(5),lineSearchStep*opts.lineSearchStep(2)));
    end
  end
  
  % est the final number features?
  % N.B. need a slight margin on dL to identify marginally stable points... which should 0, but have 
  %  v.v.v.v. small gradient
  oC=C;
  Uwb2  = (U'*reshape(W,szX(1:end-1))).^2; % Do outlier suppression for the quad est of the gradient @0
  dLRg = sqrt(sum((U'*reshape(dLW,szX(1:end-1))).^2+2*rho*min(Uwb2,mean(Uwb2(:))),2));
  if ( ~isempty(nFeat) ) % est what correct regularisor should be
    [sdLRg]=sort(abs(dLRg),'descend'); 
    if ( iter<=2 ) cFF=0; elseif( iter<200 ) cFF=.9; else cFF=.999; end;
    C=(C*(cFF)+sdLRg(nFeat+[0 1])'*[.001;.999]*(1-cFF)); % smooth out sudden value changes, prob not necessary!
    C=max(C,rho*1e-8); % stop C=0 problems
  end
  zeroFeat = C>abs(dLRg)*(1+1e-4);

  % Generalised gradient descent step on C*R+L
  % Gradient descent on L
  lipW= step./lipW0;  lipb=step./lipb0;
  dW= lipW.*dLW;
  db= lipb.*dLb;
  W = W - dW; 
  b = b - db; % grad descent step on L
  % proximal step -- i.e. shrinkage
  if ( isequal(opts.symDim(:),[1;2]) ) % decompose 
    [U,s]  =eig(reshape(W,szX(1:end-1))); V=U';  s=diag(s); % sym (pd?) features
  else
    [U,s,V]=svd(reshape(W,szX(1:end-1)),'econ'); s=diag(s); % non-sym features
  end
  % what does the new diag hessian look like?
  UddLU(:,:,iter) =tprod(tprod(U,[-1 1],H,[-1 2 3]),[1 -1 2],U,[-1 1]);
  UddL1U(:,:,iter)=repmat(tprod((U'*H1)',[-1 1],U,[-1 1]),[1 szX(2)]); % spatial only approx
  if (numel(lipW)>1)
    slip = 1./sqrt(sum((U'*reshape(lipW0,szX(1:end-1))).^2,2));
    %sqrt(sum((U'*reshape(lipW,szX(1:end-1))).^2,2)); % norm of the diag-hessian in the feature space
  else
    slip = lipW*ones(size(s));
  end
  s = sign(s).*max(0,(abs(s)-C*slip)); % prox step on s
  W = U*diag(s)*V'; W=W(:);% re-construct solution
  % N.B. wb=x_k
  actFeat=abs(s)>eps*1e4;

  J = C*R+L;
  dw=norm(oW(:)-W(:))./max(1,norm(W(:)));
  if ( iter<3 ) J0=J; maJ=max(oJ,J)*2; dw0=max(dw0,dw); end;
  maJ =maJ*(1-opts.marate)+J(1)*(opts.marate); % move-ave obj est
  madJ=maJ-J; 
  if ( opts.verb>0 )
    actFeat  = abs(s)>eps*1e3;
    fprintf('%3d)\twb=[%s]\t%5.3f + C * %5.3f = %5.4f \t|dw|=%5.3f \tL=%5.3f\tC=%5.3f\t#act=%d p#act=%d\n',iter,sprintf('%5.3f ',s(1:min(end,3))),L,R,J,norm(os-s),min(rho),C,sum(actFeat),sum(~zeroFeat(1:end-1)));    
  end

  if ( iter>1 && abs(oC-C)./max(1,abs(C))<5e-3 && ...
       (madJ<=opts.objTol(1) || madJ<=opts.objTol0(1)*J0 || dw<opts.tol(1) || dw<=opts.tol0(1)*dw0) ) 
    break; 
  end;
  if ( iter==1 ) J0=J; end;
  
end
wb=[W;b];
return

function testCase()
strue=randn(10,1).^2;
utrue=randn(40,size(strue,1)); utrue=repop(utrue,'./',sqrt(sum(utrue.^2))); 
vtrue=randn(50,size(strue,1)); vtrue=repop(vtrue,'./',sqrt(sum(vtrue.^2))); 
wtrue=utrue*diag(strue)*vtrue';% true weight
Ytrue=sign(randn(1000,1));
Y    =Ytrue + randn(size(Ytrue))*1e-2;
Xtrue=tprod(wtrue,[1 2],Y,[3]);
X    =Xtrue + randn(size(Xtrue))*1e-1;
wb0  =randn(size(X,1),size(X,2));

wb0= lr_cg(X,Y,1);
wb = lsigmals_prox(X,Y,1,'maxIter',100);
W=reshape(wb(1:end-1),size(X,1),size(X,2)); [U,s,V]=svd(W); s=diag(s);

% test with adaptive #feature selection
wb = lsigmals_prox(X,Y,-2); % with target num features
% with a seed solution to test the C determination
wb = lsigmals_prox(X,Y,-10,'wb',wb0); % with target num features

% with a warm start to test the C determination
wb1 = lsigmals_prox(X,Y,-1); 
wb2 = lsigmals_prox(X,Y,-2,'wb',wb1); 
wb  = lsigmals_prox(X,Y,-2); 

% test diag hessian approx
w=X(:,:,1);w=w(:);b=1; 
l=sqrt(w'*w); for i=1:10; w=(reshape(X,[],size(X,ndims(X)))*(w'*reshape(X,[],size(X,ndims(X))))')/l;l=sqrt(w'*w); end; 
w=w/l;
% orginal space
C  =reshape(X,[],size(X,ndims(X)))*reshape(X,[],size(X,ndims(X)))';
ddL=sum(X.*X,3);
% new space
[U,s,V]=svd(mean(X,3));s=diag(s);
UX =tprod(U,[-1 1],X,[-1 2 3]); % d x t x N
UCU=reshape(UX,[],size(X,ndims(X)))*reshape(UX,[],size(X,ndims(X)))'; % dxt x dxt
ddU=sum(UX.*UX,3); % true trans diag hessian
% efficient version?
H  =tprod(X,[1 3 -3],[],[2 3 -3]); % d x d x t
ddU2=tprod(tprod(U,[-1 1],H,[-1 2 3]),[1 -1 2],U,[-1 1]); % d x t

% approx H by it's diagonal and use that
ddUest = (U.^2)'*ddL;
ddUest2= zeros(size(ddUest));
for t=1:size(X,2);
  ddUest2(:,t) = diag(U'*diag(ddL(:,t))*U);
end
lip=sum(ddU.^2,2);
lipest=sum(ddUest.^2,2);
Cs =X(:,:)*X(:,:)';
ddUest3=diag(U'*Cs*U);
ddUest4=tprod(Cs*U,[-1 2],U,[-1 2]);