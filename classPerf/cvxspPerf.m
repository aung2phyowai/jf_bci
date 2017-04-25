function [res]=cvxspPerf(Y,dv,dims,fIdxs)
% cross-validate cross sub-problem (xsp) classifier performance
%
% [res]=cvxspPerf(Y,dv,dims,fIdxs)
%
% Inputs:
%  Y   - [N x nSubProb] set of true labels
%  dv  - [N x nSubProb x ... ] set of decision values
%  dims -- [3 x 1] indicator of where different types of dimension are in dv:
%          dims(1) = trial dims
%          dims(2:end-1) = binary sub-prob dim (classifiers)
%          dims(end) = folds dim (train/test splits)
%  fIdxs-- [N x nFolds] set of -1/0/+1 fold membership indicators, as 
%          generated by gennFold/cvtrainFn ([-ones(N,1)])
%          N.B. we only report test/excluded-set performances
% Outputs:
%  mcres   -- results structure with
%  |.di   -- dim Info struct describing how the data is arranged
%  |.fold -- per fold results
%  |     |.tstxspconf -- test set multi-class confusion matrix
%  |     |.tstxspbin  -- test set multi-class classification rate
%  |     |.tstxspauc  -- test set multi-class classification rate
%  |.tstxspconf   -- [4 x nSp x size(dv,2:end)] ave over folds, test set confusion matrix
%  |.tstxspbin    -- ave over folds, test set bin classification rate
%  |.tstxspbin_se -- std-error of ave testing set bin classification rate
%  |.tstxspauc    -- ave over folds, test set multi-class classification rate
%  |.tstxspauc_se -- std-error of ave testing set auc
%
% N.B. the 1st sub-prob dim is for actual sub-problems, and the 2nd is for the classifier 
% trained on this sub-problem, so sp=[Tst x Trn]
if ( nargin<3 || isempty(dims) ) dims=1:3; end;
if ( nargin<4 ) fIdxs=1; end;
if ( size(Y,1)~=size(dv,1) ) 
   error('decision values and targets must be the same size');
end
if(ndims(fIdxs)<=ndims(Y)) fIdxs=reshape(fIdxs,[size(fIdxs,1),1,size(fIdxs,2)]); end; %include subProb dim
trD=dims(1); spD=dims(2:end-1); fldD=dims(end);
nFolds=size(dv,fldD);
szdv=size(dv); %dv=reshape(dv,[szdv(1) prod(szdv(2:end))]); % 2-d ify
conf=zeros([4,size(Y,2),szdv([1:trD-1 trD+1:end])]);
auc =zeros([1,size(Y,2),szdv([1:trD-1 trD+1:end])]);
idx={};for d=1:ndims(dv); idx{d}=1:size(dv,d); end; % index expr to store the result
Yidx={};for d=1:ndims(Y); Yidx{d}=1:size(Y,d); end; % index for Y
for spi=1:size(Y,ndims(Y)); % loop over different sub-probs (Y's)
   Yidx{end}=spi;

   for dvi=1:prod(szdv(spD)); % loop over classifiers (dv's)
      [idx{spD}]=ind2sub(szdv(spD),dvi);
   
      for foldi=1:nFolds;
         idx{fldD}=foldi;
         conf(:,spi,idx{[1:trD-1 trD+1:end]})=...
             dv2conf(Y(Yidx{:}).*single(fIdxs(:,min(end,dvi),min(end,foldi))>=0),dv(idx{:}));
         auc (:,spi,idx{[1:trD-1 trD+1:end]})=...
             dv2auc (Y(Yidx{:}).*single(fIdxs(:,min(end,dvi),min(end,foldi))>=0),dv(idx{:}));
      end
   end
end
ftstxspbin  = conf2loss(conf);
tstxspconf  = mean(conf,dims(3)+1);
tstxspbin   = conf2loss(tstxspconf);
tstxspbin_se= sqrt(abs(sum(ftstxspbin.^2,dims(3)+1)./nFolds-tstxspbin.^2)/nFolds);
tstxspauc   = mean(auc,dims(3)+1);
tstxspauc_se= sqrt(abs(sum(auc.^2,dims(3)+1 )./nFolds-tstxspauc.^2)/nFolds);

res=struct('di',mkDimInfo(size(tstxspauc),{'perf' 'clsfr' 'subProb' 'C' 'fold'}),...
           'fold',struct('tstxspconf',conf,'tstxspbin',ftstxspbin,'tstxspauc',auc),...
           'tstxspconf',tstxspconf,...
           'tstxspbin',tstxspbin,'tstxspbin_se',tstxspbin_se,...
           'tstxspauc',tstxspauc,'tstxspauc_se',tstxspauc_se);
return;
%----------------------------------------------------------
function testCase();
dims=n2d(res.prep(end).info.res.fold.di,{'perf' 'subProb' 'fold'});
[res]=dv2mcconf(res.Y,res.prep(end).info.res.fold.f,dims,res.prep(end).info.res.fold.di(dims(3)).info.fIdxs);
