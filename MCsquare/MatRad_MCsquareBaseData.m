classdef MatRad_MCsquareBaseData
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% matRad_MCsquareBaseData Maps the matRad base data to MCsquare base data /
% phase space file
%
%
%
% References
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Copyright 2019 the matRad development team. 
% 
% This file is part of the matRad project. It is subject to the license 
% terms in the LICENSE file found in the top-level directory of this 
% distribution and at https://github.com/e0404/matRad/LICENSES.txt. No part 
% of the matRad project, including this file, may be copied, modified, 
% propagated, or distributed except according to the terms contained in the 
% LICENSE file.
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    properties
        machine         %matRad base data machine struct
        bdl_path = ''   %stores path to generated file
        nozzleToIso     %Nozzle to Isocenter Distance
        smx             %Scanning magnet X to isocenter Distance
        smy             %Scanning magnet y to isocenter Distance        
        mcSquareData    %MCsquare Phase space data struct
        selectedFocus   %array containing selected focus indices per energy
        FWHMatIso       %array containing FWHM values at iscenter for every energy
    end
    
    properties (SetAccess = private)
        stfCompressed   
        problemSigma
        dataTable       %Optical beam parameter table used for BDL generation
        energyIndex     %Indices of calculated energies
    end
    
    methods
        function obj = MatRad_MCsquareBaseData(machine,stf)
            %MatRad_MCsquareBaseData Construct an instance of the MCsquare
            %Base data format using a focus index
            
            %stfCompressed states whether mcSquareData are calculated for
            %all energies (false) or only for energies which exist in given
            %stf. If function is called without stf stfCompressed = false.
            if nargin < 2
                obj.stfCompressed = false;
            else
                obj.stfCompressed = true;
            end
            
            obj.machine = machine;
            obj.problemSigma = false;
            obj.selectedFocus = ones(numel(machine.data),1) * NaN;
            
            if isfield(machine.meta,'BAMStoIsoDist')
                obj.nozzleToIso = machine.meta.BAMStoIsoDist;
            else
                warning('No information on BAMS to isocenter distance. Using generic value of 500mm');
                obj.nozzleToIso = 500;
            end
            
            SAD = machine.meta.SAD;
            
            obj.smx = SAD;
            obj.smy = SAD;
            
            obj.mcSquareData = [];
            
            %select needed energies and according focus indices by using stf         
            if obj.stfCompressed
                tmp = [stf(:).ray];
                plannedEnergies     = [tmp.energy];
                focusIndex          = [tmp.focusIx];
                [~, ind]            = unique(plannedEnergies);
                plannedEnergies     = plannedEnergies(ind);
                focusIndex          = focusIndex(ind);
                [~ ,obj.energyIndex, ~] = intersect([machine.data(:).energy],plannedEnergies);
            
            %if no stf was refered all energies are chosen, while setting
            %the focus index for all energies to preliminary 1
            else
                plannedEnergies = [machine.data(:).energy];
                focusIndex = ones(size(plannedEnergies));
                [~ ,obj.energyIndex, ~] = intersect([machine.data(:).energy],plannedEnergies);
            end
            
            obj.selectedFocus(obj.energyIndex) = focusIndex;
             
            count = 1;
            for ii = 1:numel(obj.energyIndex)
                
                i = obj.energyIndex(ii);
                
                %look up whether MonteCarlo data are already present in 
                %machine file , if so do not recalculate
                if isfield(machine.data(i),'mcSquareData')
                    if (isempty(machine.data(i).mcSquareData) == 0)
                        obj.mcSquareData = [obj.mcSquareData, machine.data(i).mcSquareData];
                        count = count + 1;
                        continue;
                    end
                end
                
                
                %calculate mcSquareData for given energy and every focus
                %index
                data = [];
                energyData = obj.fitPhaseSpaceForEnergy(i);
                obj.FWHMatIso = [];
                for j = 1:size(machine.data(i).initFocus.sigma,1)
                    
                    tmp = energyData;
                    opticsData = obj.fitBeamOpticsForEnergy(i, j);
                    
                    f = fieldnames(opticsData);
                    for a = 1:length(f)
                        tmp.(f{a}) = opticsData.(f{a});
                    end

                data = [data; tmp];
                end
                
                obj.mcSquareData = [obj.mcSquareData, data];
                
                count = count + 1;
            end
            
            %throw out warning if there was a problem in calculating the
            %width of the Bragg peak in obj.fitBeamOpticsForEnergy
            if obj.problemSigma
                warning('Calculation of FWHM of bragg peak in base data not possible! Using simple approximation for energy spread');
            end           
        end
        
        function mcDataEnergy = fitPhaseSpaceForEnergy(obj,energyIx)
            %function to calculate mean energy and energy spread used by 
            %mcSquare for given energy
            
            i = energyIx;
            
            mcDataEnergy.NominalEnergy = obj.machine.data(i).energy;
                       
            newDepths = linspace(0,obj.machine.data(i).depths(end),numel(obj.machine.data(i).depths) * 100);
            newDose   = interp1(obj.machine.data(i).depths, obj.machine.data(i).Z, newDepths, 'spline');       

            %find FWHM w50 of bragg peak and range of 80% does fall off
            [maxV, maxI] = max(newDose);
            [~, r80ind] = min(abs(newDose(maxI:end) - 0.8 * maxV));
            r80ind = r80ind - 1;
            r80 = interp1(newDose(maxI + r80ind - 1:maxI + r80ind + 1), ...
                             newDepths(maxI + r80ind - 1:maxI + r80ind + 1), 0.8 * maxV) ...
                           + obj.machine.data(i).offset;


            [~, d50rInd] = min(abs(newDose(maxI:end) - 0.5 * maxV));
            d50rInd = d50rInd - 1;
            d50_r = interp1(newDose(maxI + d50rInd - 1:maxI + d50rInd + 1), ...
                                    newDepths(maxI + d50rInd - 1:maxI + d50rInd + 1), 0.5 * maxV);

            if (newDose(1) < 0.5 * maxV)
                [~, d50lInd] = min(abs(newDose(1:maxI) - 0.5*maxV));
                d50_l = interp1(newDose(d50lInd - 1:d50lInd + 1), ...
                                newDepths(d50lInd - 1:d50lInd + 1), 0.5 * maxV);
                w50 = d50_r - d50_l;
            %if width left of peak cannot be determined use r80 as width 
            else
                d50_l = newDepths(maxI);
                w50 = r80;
                obj.problemSigma = true;
            end

            %calcualte mean energy used my mcSquare with a formula fitted
            %to TOPAS data
            meanEnergy = @(x) 5.762374661332111e-20 * x^9 - 9.645413625310569e-17 * x^8 + 7.073049219034644e-14 * x^7 ...
                                - 2.992344292008054e-11 * x^6 + 8.104111934547256e-09 * x^5 - 1.477860913846939e-06 * x^4 ...
                                + 1.873625800704108e-04 * x^3 - 1.739424343114980e-02 * x^2 + 1.743224692623838e+00 * x ...
                                + 1.827112816899668e+01;
            mcDataEnergy.MeanEnergy = meanEnergy(r80);
            
            %calculate energy straggling using formulae deducted from paper 
            %"An analytical approximation of the Bragg curve for therapeutic 
            %proton beams" by T. Bortfeld et al.
            totalSigmaSq = ((w50) / 6.14)^2;
                     
            totalSpreadSq = @(x) 2.713311945114106e-20 * x^9 - 4.267890251195303e-17 * x^8 + 2.879118523083018e-14 * x^7 ...
                                    - 1.084418008735459e-11 * x^6 + 2.491796224784373e-09 * x^5 - 3.591462823163767e-07 * x^4 ...
                                    + 3.232810400304542e-05 * x^3 - 1.584729282376364e-03 * x^2 + 5.228413840446568e-02 * x ...
                                    - 6.547482267336220e-01;
            % use formula deducted from Bragg Kleeman rule to calcuate
            % energy straggling given the total sigma and the range
            % straggling
            energySpread = (totalSigmaSq - totalSpreadSq(r80)) / (0.022^2 * 1.77^2 * mcDataEnergy.MeanEnergy^(2*1.77-2));
            energySpread(energySpread < 0) = 0;
            mcDataEnergy.EnergySpread = sqrt(energySpread);         
        end
            
        function mcDataOptics = fitBeamOpticsForEnergy(obj,energyIx, focusIndex)
            %function to calculate beam optics used by mcSquare for given
            %energy
            
            i = energyIx;        

            %calculate geometric distances and extrapolate spot size at nozzle
            SAD = obj.machine.meta.SAD;
            z     = -(obj.machine.data(i).initFocus.dist(focusIndex,:) - SAD);
            sigmaSq = obj.machine.data(i).initFocus.sigma(focusIndex,:).^2;

            %fit Courant-Synder equation to data using ipopt, formulae
            %given in mcSquare documentation
            sigmaNull = sqrt(interp1(z,sigmaSq,0));

            qRes = @(rho, sigmaT) (sigmaSq -  (sigmaNull^2 - 2*sigmaNull*rho*sigmaT.*z + sigmaT^2.*z.^2));

            funcs.objective = @(x) sum(qRes(x(1), x(2)).^2);
            funcs.gradient  = @(x) [  2 * sum(qRes(x(1), x(2)) .* (2 * sigmaNull * x(2) * z)); 
                                      2 * sum(qRes(x(1), x(2)) .* (2 * sigmaNull * x(1) * z  - 2 * x(2) * z.^2))];     

            options.lb = [-0.99, -Inf];
            options.ub = [ 0.99,  Inf];

            options.ipopt.hessian_approximation = 'limited-memory';
            options.ipopt.limited_memory_update_type = 'bfgs';
            options.ipopt.print_level = 1;

            start = [0.9; 0.1];
            [result, ~] = ipopt (start, funcs, options);
            rho    = result(1);
            sigmaT = result(2);

            %calculate divergence, spotsize and correlation at nozzle
            DivergenceAtNozzle  = sigmaT;
            SpotsizeAtNozzle    = sqrt(sigmaNull^2 - 2 * rho * sigmaNull * sigmaT * obj.nozzleToIso + sigmaT^2 * obj.nozzleToIso^2);
            CorrelationAtNozzle = (rho * sigmaNull - sigmaT * obj.nozzleToIso) / SpotsizeAtNozzle;
            

            %save calcuated beam optics data in mcData
            mcDataOptics.ProtonsMU     = 1e6;

            mcDataOptics.Weight1       = 1;
            mcDataOptics.SpotSize1x    = SpotsizeAtNozzle;
            mcDataOptics.Divergence1x  = DivergenceAtNozzle;
            mcDataOptics.Correlation1x = CorrelationAtNozzle;
            mcDataOptics.SpotSize1y    = SpotsizeAtNozzle;
            mcDataOptics.Divergence1y  = DivergenceAtNozzle;
            mcDataOptics.Correlation1y = CorrelationAtNozzle;

            mcDataOptics.Weight2       = 0;
            mcDataOptics.SpotSize2x    = 0;
            mcDataOptics.Divergence2x  = 0;
            mcDataOptics.Correlation2x = 0;
            mcDataOptics.SpotSize2y    = 0;
            mcDataOptics.Divergence2y  = 0;
            mcDataOptics.Correlation2y = 0;
            mcDataOptics.FWHMatIso = 2.355 * sigmaNull;
        end
        
        function obj = writeTopasData(obj,filepath,stf,fracHistories,w)
            %writeToBDLfile write the base data to file "filepath"
            
            %look up focus indices
            focusIndex = obj.selectedFocus(obj.energyIndex);
            
            %save mcData acording to used focus index in dataTable
            selectedData = [];
            for i = 1:numel(focusIndex)
                
                selectedData = [selectedData, obj.mcSquareData(focusIndex(i), i)];
            end
                                    
            machine = obj.machine;
            
            
            energies = [selectedData.NominalEnergy];
            counter = 1;
            for i = 1:stf.numOfRays
                
                for j = 1:stf.numOfBixelsPerRay(i)
                    bixelEnergy = stf.ray(i).energy(j);
                    [~,ixTmp,~] = intersect(energies, bixelEnergy);
                    dataTOPAS(counter).energy = selectedData(ixTmp).MeanEnergy;
                    dataTOPAS(counter).energySpread = selectedData(ixTmp).EnergySpread;
                    dataTOPAS(counter).posX = stf.ray(i).rayPos_bev(1);
                    dataTOPAS(counter).posY = stf.ray(i).rayPos_bev(3);
                    dataTOPAS(counter).spotSize = selectedData(ixTmp).SpotSize1x;
                    dataTOPAS(counter).divergence = selectedData(ixTmp).Divergence1x;
                    dataTOPAS(counter).correlation = selectedData(ixTmp).Correlation1x;
                    dataTOPAS(counter).current = fracHistories*round(1e6*w(counter));
                    
                    counter = counter + 1;
                    
                end
            end
            
            [~,ixSorted] = sort([dataTOPAS(:).energy]);
            dataTOPAS = dataTOPAS(ixSorted);
            
                try 
                    fileID = fopen([filepath,'beamSetup_matRad_plan_field1.txt'],'w');

                    fprintf(fileID,'i:Ts/ShowHistoryCountAtInterval = 1500000\n');
                    fprintf(fileID,'s:Sim/PlanLabel = "simData_matrad_plan_field1_run" + Ts/Seed\n');
                    fprintf(fileID,'d:Sim/GantryAngle = %.6f deg\n', stf.gantryAngle);
                    fprintf(fileID,'d:Sim/CouchAngle = %.6f deg\n', stf.couchAngle);
                    fprintf(fileID,'s:Sim/ParticleName = "proton"\n');
                    fprintf(fileID,'u:Sim/ParticleMass = 1.0\n');
                    fprintf(fileID,'i:Sim/NbThreads = 0\n');
                    fprintf(fileID,'d:Tf/TimelineStart = 0. ms\n');
                    fprintf(fileID,'d:Tf/TimelineEnd = %i ms\n', 10 * stf.totalNumOfBixels);
                    fprintf(fileID,'i:Tf/NumberOfSequentialTimes = %i\n', stf.totalNumOfBixels);
                    fprintf(fileID,'dv:Tf/Beam/Spot/Times = %i ', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string(linspace(10,stf.totalNumOfBixels*10,stf.totalNumOfBixels))));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/Energy/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/Energy/Times = Tf/Beam/Spot/Times ms\n');
                    fprintf(fileID,'dv:Tf/Beam/Energy/Values = %i ', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string([dataTOPAS(:).energy])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/EnergySpread/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/EnergySpread/Times = Tf/Beam/Spot/Times ms');
                    fprintf(fileID,'dv:Tf/Beam/EnergySpread/Values = %i ', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string([dataTOPAS(:).energySpread])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/Sigma/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/Sigma/Times = Tf/Beam/Spot/Times ms');
                    fprintf(fileID,'dv:Tf/Beam/Sigma/Values = %i ', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string([dataTOPAS(:).spotSize])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/SigmaPrime/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/SigmaPrime/Times = Tf/Beam/Spot/Times ms');
                    fprintf(fileID,'dv:Tf/Beam/SigmaPrime/Values = %i ', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string([dataTOPAS(:).divergence])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/Correlation/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/Correlation/Times = Tf/Beam/Spot/Times ms');
                    fprintf(fileID,'dv:Tf/Beam/Correlation/Values = %i ', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string([dataTOPAS(:).correlation])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'dv:Tf/Beam/AngleX/Values = %i ', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string(num2str(zeros(stf.totalNumOfBixels,1),'%.6f'))));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/AngleY/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/AngleY/Times = Tf/Beam/Spot/Times ms\n');
                    fprintf(fileID,'dv:Tf/Beam/AngleY/Values = %i', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string(num2str(zeros(stf.totalNumOfBixels,1),'%.6f'))));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/PosX/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/PosX/Times = Tf/Beam/Spot/Times ms\n');
                    fprintf(fileID,'dv:Tf/Beam/PosX/Values = %i', stf.totalNumOfBixels);
                    fprintf(fileID,strjoin(string([dataTOPAS(:).posX])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/PosY/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/PosY/Times = Tf/Beam/Spot/Times ms\n');
                    fprintf(fileID,'dv:Tf/Beam/PosY/Values = %i', stf.totalNumOfBixels); 
                    fprintf(fileID,strjoin(string([dataTOPAS(:).posY])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'s:Tf/Beam/Current/Function = "Step"\n');
                    fprintf(fileID,'dv:Tf/Beam/Current/Times = Tf/Beam/Spot/Times ms\n');
                    fprintf(fileID,'iv:Tf/Beam/Current/Values = %i', stf.totalNumOfBixels); 
                    fprintf(fileID,strjoin(string([dataTOPAS(:).current])));
                    fprintf(fileID,'\n');
                    fprintf(fileID,'d:So/PencilBeam/BeamEnergy = Tf/Beam/Energy/Value MeV * Sim/ParticleMass\n');

                    fprintf(fileID,'d:Ge/Patient/TransX      = %.6f mm\n', 61.189329);      %% needs to be fixed
                    fprintf(fileID,'d:Ge/Patient/TransY      = %.6f mm\n', 30.323580);      %% needs to be fixed
                    fprintf(fileID,'d:Ge/Patient/TransZ      = %.6f mm\n', -105.138052);    %% needs to be fixed
                    fprintf(fileID,'d:Ge/Patient/RotX=0. deg\n');                           %% needs to be fixed
                    fprintf(fileID,'d:Ge/Patient/RotY=0. deg\n');                           %% needs to be fixed
                    fprintf(fileID,'d:Ge/Patient/RotZ=0. deg\n');                           %% needs to be fixed
                    fprintf(fileID,'includeFile = ./matRad_RSPcube.txt\n');                  
                    
                    fprintf(fileID,'###################\n\n#Beam\n');
                    TOPAS_beamSetup = fopen(['TOPAS_beamSetup_generic_' pln.radiationMode '.txt'],'r');
                    
                    % copy standard values from TOPAS_beamSetup
                    while ~feof(TOPAS_beamSetup)
                        strLine = fgets(TOPAS_beamSetup); %# read line by line
                        fprintf(fileID,'%s',strLine);
                    end
                    
                    fprintf(fileID,'\n');
                    
                    fclose(fileID);                                          

                catch MException
                    error(MException.message);
                end
            end
        
            
        function obj = writeMCsquareData(obj,filepath)
            %writeToBDLfile write the base data to file "filepath"
            
            %look up focus indices
            focusIndex = obj.selectedFocus(obj.energyIndex);
            
            %save mcData acording to used focus index in dataTable
            selectedData = [];
            for i = 1:numel(focusIndex)
                
                selectedData = [selectedData, obj.mcSquareData(focusIndex(i), i)];
            end
                                    
            machine = obj.machine;
            
            selectedData = rmfield(selectedData, 'FWHMatIso');
                
            try

                fileID = fopen(filepath,'w');

                %Header
                %fprintf(fileID,'--matRad: Beam Model for machine %s (%s)--\n',machine.meta.machine,machine.meta.dataType);
                fprintf(fileID,'--UPenn beam model (double gaussian)--\n');
                fprintf(fileID,'# %s\n',machine.meta.description);
                fprintf(fileID,'# created by %s on %s\n\n',machine.meta.created_by,machine.meta.created_on);

                fprintf(fileID,'Nozzle exit to Isocenter distance\n');
                fprintf(fileID,'%.1f\n\n',obj.nozzleToIso);

                fprintf(fileID,'SMX to Isocenter distance\n');
                fprintf(fileID,'%.1f\n\n',obj.smx);

                fprintf(fileID,'SMY to Isocenter distance\n');
                fprintf(fileID,'%.1f\n\n',obj.smy);

                fprintf(fileID,'Beam parameters\n%d energies\n\n',stf.totalNumOfBixels);

                fn = fieldnames(selectedData);
                for names = 1:size(fn,1)
                    fprintf(fileID, fn{names});
                    fprintf(fileID, '\t');
                end
                fprintf(fileID, '\n');

                for k = 1:stf.totalNumOfBixels
                    for m = 1:numel(fn)
                        fprintf(fileID, '%g', selectedData(k).(fn{m}));
                        fprintf(fileID, '\t');
                    end
                    fprintf(fileID, '\n');
                 end

                fclose(fileID);                                          

                obj.bdl_path = filepath;

            catch MException
                error(MException.message);
            end
            
        end
        
          
        function obj = saveMatradMachine(obj,name)
            %save previously calculated mcSquareData in new baseData file
            %with given name
            
            machine = obj.machine;
            [~ ,energyIndex, ~] = intersect([obj.machine.data(:).energy], [obj.mcSquareData(:).NominalEnergy]);
            
            machineName = [obj.machine.meta.radiationMode, '_', name];
            
            count = 1;
            for i = energyIndex'
               
                machine.data(i).mcSquareData = obj.mcSquareData(:,count);
                
                count = count + 1;
            end
            
            save(strcat('../../', machineName, '.mat'),'machine');
        end
   end
end

