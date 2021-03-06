% function [nll, grad] = InstanceNegLogLikelihood(X, y, theta, modelParams)
% returns the negative log-likelihood and its gradient, given a CRF with parameters theta,
% on data (X, y). 
%
% Inputs:
% X            Data.                           (numInstances x numImageFeatures matrix)
%              X(:,1) is all ones, i.e., it encodes the intercept/bias term.
% y            Data labels.                    (numInstances x 1 vector)
% theta        CRF weights/parameters.         (numParams x 1 vector)
%              These are shared among the various singleton / pairwise features.
% modelParams  Struct with two fields:
%   .numHiddenStates     in our case, set to 26 (26 possible characters)
%   .numObservedStates   in our case, set to 2  (each pixel is either on or off)
%
% Outputs:
% nll          Negative log-likelihood of the data.    (scalar)
% grad         Gradient of nll with respect to theta   (numParams x 1 vector)

function [nll, grad] = InstanceNegLogLikelihood(X, y, thetas, modelParams)

    % featureSet is a struct with two fields:
    %    .numParams - the number of parameters in the CRF (this is not numImageFeatures
    %                 nor numFeatures, because of parameter sharing)
    %    .features  - an array comprising the features in the CRF.
    %
    % Each feature is a binary indicator variable, represented by a struct 
    % with three fields:
    %    .var          - a vector containing the variables in the scope of this feature
    %    .assignment   - the assignment that this indicator variable corresponds to
    %    .paramIdx     - the index in theta that this feature corresponds to
    %
    % For example, if we have:
    %   
    %   feature = struct('var', [2 3], 'assignment', [5 6], 'paramIdx', 8);
    %
    % then feature is an indicator function over Y_2 and Y_3, which takes on a value of 1
    % if Y_2 = 5 and Y_3 = 6 (which would be 'e' and 'f'), and 0 otherwise.
    % Its contribution to the log-likelihood would be theta(8) if it's 1, and 0 otherwise.
    %
    % If you're interested in the implementation details of CRFs, 
    % feel free to read through GenerateAllFeatures.m and the functions it calls!
    % For the purposes of this assignment, though, you don't
    % have to understand how this code works. (It's complicated.)
    
    featureSet = GenerateAllFeatures(X, y, modelParams);

    % Use the featureSet to calculate nll and grad.
    % This is the main part of the assignment, and it is very tricky - be careful!
    % You might want to code up your own numerical gradient checker to make sure
    % your answers are correct.
    %
    % Hint: you can use CliqueTreeCalibrate to calculate logZ effectively. 
    %       We have halfway-modified CliqueTreeCalibrate; complete our implementation 
    %       if you want to use it to compute logZ.
    
    %%%
    % Your code here:

    factors = factors_from_features(featureSet.features, thetas, modelParams);

    P = CreateCliqueTree(factors);
    [ P logZ ] = CliqueTreeCalibrate(P, 0);

    reg_cost = regularization_cost(modelParams.lambda, thetas);

    [unweighted_counts weighted_counts] = feature_counts(y, featureSet.features, thetas);

    nll = logZ - sum(weighted_counts) + reg_cost;

    % pyx = exp (-logZ + weighted_counts);

    grad = calculate_gradient(P, featureSet.numParams, featureSet.features, unweighted_counts, modelParams.lambda, thetas);

    return;
end

%% regularization_cost: calculates it
function [cost] = regularization_cost(lambda, thetas)
    sq_thetas = thetas .^ 2;
    cost = lambda / 2.0 * sum(sq_thetas);
    return;
end

%% factors_from_features: see the name
function [factors] = factors_from_features(features, thetas, modelParams)
    factors = repmat(EmptyFactorStruct(), length(features), 1);
    for i = 1:length(features),
        factors(i).var = features(i).var;
        factors(i).card = ones(1, length(features(i).var)) .* modelParams.numHiddenStates;
        factors(i).val = ones(1, prod(factors(i).card));
        factors(i) = SetValueOfAssignment(factors(i), features(i).assignment, exp(thetas(features(i).paramIdx)));
    end
    return;
end

%% feature_counts: see description
function [counts, weighted] = feature_counts(Y, features, thetas)
    counts = zeros(length(features), 1);
    weighted = zeros(length(features), 1);
    for i = 1:length(features)
        if all(Y(features(i).var)==features(i).assignment)
            counts(i) = 1;
            weighted(i) = thetas(features(i).paramIdx);
        end
    end
    return;
end

%% calculate_gradient: see description
function [grad] = calculate_gradient(P, numParams, features, unweighted_counts, lambda, thetas)
    grad = zeros(1, numParams);
    ed = zeros(1,numParams);
    etheta = zeros(1,numParams);
    for j = 1:length(features)
        ed(features(j).paramIdx) = ed(features(j).paramIdx) + unweighted_counts(j);
    end
    for i = 1:length(features)
        Idx = features(i).paramIdx;
        cliqueIdx = 0;
        for j = 1:length(P.cliqueList)
            if all(ismember(features(i).var,P.cliqueList(j).var))
                cliqueIdx = j;
                break;
            end
        end
        VarToEle = setdiff(P.cliqueList(cliqueIdx).var, features(i).var);
        tempFactor = FactorMarginalization(P.cliqueList(cliqueIdx),VarToEle);
        PIdx = AssignmentToIndex(features(i).assignment,tempFactor.card);
        etheta(Idx) = etheta(Idx) + tempFactor.val(PIdx) / sum(tempFactor.val);
    end
    for i = 1:numParams
        grad(i) = etheta(i) - ed(i) + lambda*thetas(i);
    end
    
end
