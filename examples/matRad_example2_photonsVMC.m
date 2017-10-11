%% Example: Photon Treatment Plan using VMC++ dose calculation
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Copyright 2017 the matRad development team. 
% 
% This file is part of the matRad project. It is subject to the license 
% terms in the LICENSE file found in the top-level directory of this 
% distribution and at https://github.com/e0404/matRad/LICENSES.txt. No part 
% of the matRad project, including this file, may be copied, modified, 
% propagated, or distributed except according to the terms contained in the 
% LICENSE file.
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%
% In this example we will show 
% (i) how to load patient data into matRad
% (ii) how to setup a photon dose calculation based on the VMC++ Monte Carlo algorithm 
% (iii) how to inversely optimize the beamlet intensities directly from command window in MATLAB. 
% (iv) how to visualize the result

%% Patient Data Import
% Let's begin with a clear Matlab environment and import the boxphantom
% into your workspace. 
clc,clear,close all;
load('BOXPHANTOM.mat');

%% Treatment Plan
% The next step is to define your treatment plan labeled as 'pln'. This 
% structure requires input from the treatment planner and defines the most
% important cornerstones of your treatment plan.

pln.radiationMode = 'photons';  
pln.machine       = 'Generic';
pln.bioOptimization = 'none';    
pln.gantryAngles    = [0];
pln.couchAngles     = [0];
pln.bixelWidth      = 10;
pln.numOfFractions  = 30;
pln.numOfBeams      = numel(pln.gantryAngles);
pln.numOfVoxels     = prod(ct.cubeDim);
pln.voxelDimensions = ct.cubeDim;
pln.isoCenter       = ones(pln.numOfBeams,1) * matRad_getIsoCenter(cst,ct,0);
pln.runSequencing   = 0;
pln.runDAO          = 0;

%% Generate Beam Geometry STF
stf = matRad_generateStf(ct,cst,pln);

%% Dose Calculation
% Calculate dose influence matrix for unit pencil beam intensities using 
% the VMC++ monte carlo algorithm. We define the number of photons 
% simulated per beamlet to be 700. You can find compatible VMC++ files at
% http://www.cerr.info/download.php which have to located in
%  matRadrootDirectory\vmc++.
dij = matRad_calcPhotonDoseVmc(ct,stf,pln,cst);

%% Inverse Optimization for IMRT
resultGUI = matRad_fluenceOptimization(dij,cst,pln);

%% Plot the Resulting Dose Slice
% Just let's plot the transversal iso-center dose slice
slice = round(pln.isoCenter(1,3)./ct.resolution.z);
figure,
imagesc(resultGUI.physicalDose(:,:,slice)),colorbar, colormap(jet)

%%
% Exemplary, we show how to obtain the dose in the target and plot the histogram
ixTarget     = cst{2,4}{1};
doseInTarget = resultGUI.physicalDose(ixTarget);
figure
histogram(doseInTarget);
title('dose in target'),xlabel('[Gy]'),ylabel('#');

%% Start the GUI for Visualization
matRadGUI
