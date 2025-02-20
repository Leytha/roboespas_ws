% Este programa lee los vectores de posici�n y fuerzas de la herramienta del robot en
% un archivo .mat y los archivos proporcionados por la Kinect en un archivo CSV.
% Transforma estas tablas en una tabla .trc para que pueda
% ser utilizada por OpenSim y realizar una cinem�tica inversa. Una vez
% obtenido el archivo .mot, mediante IK, con el registro de los movimientos de cada
% coordenada del modelo, se puede lanzar un visualizador para que
% represente estos movimientos. El programa tras calcular la IK, calcula las fuerzas externas
% que se aplican sobre el brazo del paciente, para, a continuaci�n, realizar un an�lisis CMC,
% que devolver� los valores de excitationes y activaciones. Tras este c�lculo, se ejecuta una
% �ltima herramienta (Forward Dynamics) que calcula el resto de valores necesarios para la investigaci�n.
% Adicionalmente el programa ejecuta una
% dinamica inversa a partir del archivo .mot, a la que se le podr�a sumar
% unas fuerzas externas que interviniesen en el proceso (las realizadas por
% el brazo robotico).

clear all
close all
clc
import org.opensim.modeling.*
format long
pause(2);
%% INPUTS

%   <<<<<<<<<<<<<MODIFICABLES:>>>>>>>>>>>>
% Masa del sujeto
masaTotal=67;
% mass=4.77882; %4.77882 es la que tiene el modelo por defecto
mass = masaTotal*0.55; % la masa del tronco superior es aproximadamente el 55% de la masa  total

escalarModelo=false;
methodIIWA_FD= 'Screw Theory'; %'Matlab toolbox'   Screw Theory
modeladoMuscular='Sano_Millard'; %'Spastic_Millard'   Sano_Thelen   Spastic_Thelen   Sano_Millard
grado=4; % Regresi�n fuerzas Screw Theory
version='V2'; % V2 %'V1' para usar el modelo de Eduardo, 'V2' para usar el modelo de Anaelle

file_path = which(mfilename);
id_ch_folders = find(file_path =='\');
pathOpenSimControl = file_path(1:id_ch_folders(end-2));
disp(['Using OpenSimControl path: ', pathOpenSimControl]);

pathOpenSim = ['C:\OpenSim ', char(org.opensim.modeling.opensimCommon.GetVersion())];
% title=strcat('Selecciona el directorio de instalaci�n de OpenSim') ;
% pathOpenSim = uigetdir(pathOpenSim, title);
% if (pathOpenSim == 0)
%     ME = MException('Main:NoOpenSimPath', 'No OpenSim path selected');
%     throw(ME);
% end
% disp(['Using OpenSim installation path: ', pathOpenSim]);

% Path model folder
CD_model= [pathOpenSimControl, 'ROBOESPAS_FLEXION'];

%% Load data
% Get model name, load plugin in OpenSim if its spastic
switch modeladoMuscular
    case 'Spastic_Thelen'
        opensimCommon.LoadOpenSimLibrary("..\Plugins\SpasticThelenMuscleModel.dll")
        MODELO = ['Arm_Flexion_SpasticThelen_', version, '.osim'];
    case 'Spastic_Millard'
        opensimCommon.LoadOpenSimLibrary("..\Plugins\SpasticMillardMuscleModel.dll")
        MODELO = ['Arm_Flexion_SpasticMillard_', version, '.osim'];
    case 'Sano_Thelen'
        MODELO = ['Arm_Flexion_Thelen_', version, '.osim'];
    case 'Sano_Millard'
        MODELO = ['Arm_Flexion_Millard_', version, '.osim'];
end

% Modificaciones en el modelo previas a su uso (posici�n por defecto, coords. bloqueadas, rango de mvto...)
model = f_ModelCoordChanges(CD_model,MODELO);
model.print(strcat(CD_model,'\',MODELO))

% createActuatorsFile([CD_model, '\', MODELO]);
% Load trial
IMUpath = strcat(CD_model, '\IMUData');
load(strcat(IMUpath, '\trialLab.mat'));
   
% Load IIWA-FT data
% load(strcat(pathOpenSimControl, 'TrayectoriasGrabadas\pruebaIIWA_FT.mat'));

%% Obtain Handle trajectory from robot TCP
% FKHandle = FK(Datos{1}.trayectoria)';
FKHandle = FK(trial.Trajectory.Trial.JointTrajectory)';
CMarkers.Handle = f_HandleCoordModifications(FKHandle(:,1:3), model);
V_IIWA = CMarkers.Handle;

% Creo una trcTable nueva
[TrcTableCreada] = f_CreateTRCTable(trial.Trajectory.Trial.Timestamps,CMarkers,'IIWA');

% Lo imprimo en un archivo .trc (Coordenadas cartesianas espaciales)

%cd(CD_trc)
CD_trc=strcat(CD_model,'\CCartesianas');
org.opensim.modeling.TRCFileAdapter.write(TrcTableCreada,[CD_trc, '\Lab.trc']);
pause(0.2);

%Variables para compensar los valores de los momentos:
V_OpenSim=CMarkers.Handle;

%% Create Xsens file from trial
f_createXsensFile(trial, IMUpath);

%% Convert IMU data to OpenSim format
% Build an Xsens Settings Object. 
% Instantiate the Reader Settings Class
xsensSettings = XsensDataReaderSettings(strcat(IMUpath, '\myIMUMappings.xml'));
% Instantiate an XsensDataReader
xsens = XsensDataReader(xsensSettings);
% Get a table reference for the data
tables = xsens.read(strcat(IMUpath, '/'));
% get the trial name from the settings
trialName = char(xsensSettings.get_trial_prefix());

% Get Orientation Data as quaternions
quatTable = xsens.getOrientationsTable(tables);
% Write to file
STOFileAdapterQuaternion.write(quatTable,  [IMUpath, '\', trialName 'orientations.sto']);

%% Calibrate OpenSim model
% Set variables to use
modeloPath = [CD_model, '\', MODELO];
orientationsFileName = [IMUpath,'/',trialName,'orientations.sto']; % The path to orientation data for calibration 
sensor_to_opensim_rotation = Vec3(0, -pi/2, 0);% The rotation of IMU data to the OpenSim world frame 
% baseIMUName = 'humerus_imu';                     % The base IMU is the IMU on the base body of the model that dictates the heading (forward) direction of the model.
% baseIMUHeading = 'y';                           % The Coordinate Axis of the base IMU that points in the heading direction. 
visulizeCalibration = false;                     % Boolean to Visualize the Output model

% Instantiate an IMUPlacer object
imuPlacer = IMUPlacer();

% Set properties for the IMUPlacer
imuPlacer.setModel(model);
imuPlacer.set_model_file(modeloPath);
imuPlacer.set_orientation_file_for_calibration(orientationsFileName);
imuPlacer.set_sensor_to_opensim_rotations(sensor_to_opensim_rotation);
% imuPlacer.set_base_imu_label(baseIMUName);
% imuPlacer.set_base_heading_axis(baseIMUHeading);

% Run the IMUPlacer
imuPlacer.run(visulizeCalibration);

% Get the model with the calibrated IMU's
model = imuPlacer.getCalibratedModel();

% Print the calibrated model to file.
model.print(strrep(modeloPath, '.osim', '_calibrated.osim') );
MODELO = strrep(MODELO, '.osim', '_calibrated.osim');

pause(2)
%% Obtain IK motion from orientation tracking
% Set variables to use
visualizeTracking = false;  % Boolean to Visualize the tracking simulation
startTime = trial.DelsysSensors.Trial.Sensor1.IMU.Timestamps(1); % Start time (in seconds) of the tracking simulation. 
endTime = trial.DelsysSensors.Trial.Sensor1.IMU.Timestamps(end); % End time (in seconds) of the tracking simulation.
resultsDirectory = [CD_model,'\IKResults'];

% Instantiate an InverseKinematicsTool
imuIK = IMUInverseKinematicsTool();
 
% Set the model path to be used for tracking
imuIK.setModel(model);
imuIK.set_model_file([CD_model, '\', MODELO]);
imuIK.set_orientations_file(orientationsFileName);
imuIK.set_sensor_to_opensim_rotations(sensor_to_opensim_rotation)
% Set marker file
imuIK.loadMarkersFile(strcat(CD_model, '\CCartesianas\Lab.trc'));
imuIK.set_marker_file(strcat(CD_model, '\CCartesianas\Lab.trc'));
% Set time range in seconds
imuIK.set_time_range(0, startTime); 
imuIK.set_time_range(1, endTime);   
% Set a directory for the results to be written to
imuIK.set_results_directory(resultsDirectory)
% Set output accuracy
imuIK.set_accuracy(20);
% Run IK
imuIK.run(visualizeTracking);


ImuMotionStr = strcat('ik_', trialName, 'orientations.mot');
motImuFilePath=strcat(CD_model,'\IKResults\',ImuMotionStr);

%% Perform IK over the handle data using OpenSense resulting motion as reference
%  En OpenSim: realizar una IK con los datos del marker del Handle y a�adir en la casilla 'coordinate data for trial' los
%  resultados de OpenSense (ImuMotionStr) con un peso de 0.1 (esto se cambia en la pesta�a 'Weights')
OutputMotionStr = 'Movimiento.mot';
CD_CArticulares=strcat(CD_model,'\CArticulares');
fCinInv(CD_model,CD_CArticulares,model,'Lab.trc',OutputMotionStr,ImuMotionStr);
motFilePath=strcat(CD_CArticulares,'\',OutputMotionStr);
pause(2);

%% Create External Loads
% t = trial.DelsysSensors.Trial.Sensor1.IMU.Timestamps;
% ForceAndTorque = zeros(length(t),9);
% ForceAndTorque(:,2) = ones(length(ForceAndTorque),1).*(-2.0);
% ForceAndTorque(:,4)= 0;
% ForceAndTorque(:,5)= -0.08; %posicion de donde se aplica la fuerza respecto al s.c de la mano
% ForceAndTorque(:,6)= 0;
% % Guardar las ExternalLoads en una variable de OpenSim    
% %Guardo todos los datos en un Storage -> ExternalForcesStorage
% ExternalForcesTorquesStorage=org.opensim.modeling.Storage();
% ExternalForcesTorquesStorage.setName('ExternalLoads.mot');   %
% ExternalForcesTorquesStorage.setInDegrees(true); %Igual que en Gait2354
% % Time=TrcTableCreada.getIndependentColumn;
% %     Force=ForceAndTorque(:,1:3);
% %     Torque=ForceAndTorque(:,7:9);
% ColumnLabels=org.opensim.modeling.ArrayStr();
% ColumnLabels.append('time');
% ColumnLabels.append('hand_force_vx');
% ColumnLabels.append('hand_force_vy');
% ColumnLabels.append('hand_force_vz');
% ColumnLabels.append('hand_force_px');
% ColumnLabels.append('hand_force_py');
% ColumnLabels.append('hand_force_pz');
% ColumnLabels.append('hand_torque_x');
% ColumnLabels.append('hand_torque_y');
% ColumnLabels.append('hand_torque_z');
% ExternalForcesTorquesStorage.setColumnLabels(ColumnLabels);
% %Meto los valores COMO STATEVECTORS
% for i=1:length(t(1,:))
%     fila=org.opensim.modeling.StateVector();
%     v=org.opensim.modeling.Vector();
%     v.resize(int16(length(ForceAndTorque(1,:))));
%     for j = 1:length(ForceAndTorque(1,:))
%         v.set(int16(j-1),ForceAndTorque(i,j)); %Vector empieza desde 0
%         fila.setStates(1,v);
%         fila.setTime(t(i));
%         %             size=fila.getSize;
%     end
%     ExternalForcesTorquesStorage.append(fila);
% end
% ExternalForcesTorquesStorage.print(strcat(CD_model,'\ForcesAndTorques\ExternalLoads.mot'));
% External_Force_FT=org.opensim.modeling.ExternalForce(ExternalForcesTorquesStorage,'hand_force_v','hand_force_p','hand_torque_','hand','ground','hand'); 
% External_Force_FT.setName('TCP_ExternalForce');
% External_Force_FT.setAppliedToBodyName('hand');        %%%%%
% % External_Force.setForceExpressedInBodyName('hand');  % No aplica en
% % el caso de que la fuerza se aplique sobre un body (Instrucciones de
% % OpenSim)
% External_Force_FT.print(strcat(CD_model,'\ForcesAndTorques\ExternalForce.xml'));
% clear ColumnLabels fila v
% External_Loads_FT=org.opensim.modeling.ExternalLoads();
% External_Loads_FT.adoptAndAppend(External_Force_FT);
% External_Loads_FT.setLowpassCutoffFrequencyForLoadKinematics(6);
% External_Loads_FT.setDataFileName('ExternalLoads.mot');
% % External_Loads_FT.setExternalLoadsModelKinematicsFileName(motFilePath); NO ES NECESARIO
% xmlExternalLoadsFileName_FT=strcat(CD_model,'\ForcesAndTorques\ExternalLoads.xml');
% External_Loads_FT.print(xmlExternalLoadsFileName_FT);
% motExternalLoadsFileName_FT=strcat(CD_model,'\ForcesAndTorques\ExternalLoads.mot');

%% Obtenci�n de las fuerzas y momentos en el TCP
cd(CD_model);
if isequal(methodIIWA_FD,'Screw Theory')
   [ForceAndTorque,stampsST] = IiwaForwardDynamics(trial); % SCREW THEORY

   % Limpio la gr�fica por minimos cuadrados
   % Fuerza en X
    x=stampsST(1:end);
    y=ForceAndTorque(:,1);
    px = polyfit(x,y,grado);
    ForceAndTorqueLimpio(:,1) = polyval(px,x)';
    % Fuerza en Y
    y=ForceAndTorque(:,2);
    py = polyfit(x,y,grado);
    ForceAndTorqueLimpio(:,2) = polyval(py,x)';
    % Fuerza en Z
    y=ForceAndTorque(:,3);
    pz = polyfit(x,y,grado);
    ForceAndTorqueLimpio(:,3) = polyval(pz,x)';
    % Momento en X
    x=stampsST(1:end);
    y=ForceAndTorque(:,4);
    px = polyfit(x,y,grado);
    ForceAndTorqueLimpio(:,4) = polyval(px,x)';
    % Momento en Y
    y=ForceAndTorque(:,5);
    py = polyfit(x,y,grado);
    ForceAndTorqueLimpio(:,5) = polyval(py,x)';
    % Momento en Z
    y=ForceAndTorque(:,6);
    pz = polyfit(x,y,grado);
    ForceAndTorqueLimpio(:,6) = polyval(pz,x)';
    ForceAndTorque=ForceAndTorqueLimpio;
    clear x y px py pz ForceAndTorqueLimpio

    % Cambio el sentido de todos los vectores para que actuen sobre el brazo
    % del paciente
    Fx=-ForceAndTorque(:,1);
    Fy=-ForceAndTorque(:,2);
    Fz=-ForceAndTorque(:,3);

    Tx=ForceAndTorque(:,4); % El sentido de los torques se trabaja a posteriori
    Ty=ForceAndTorque(:,5);
    Tz=ForceAndTorque(:,6);

    ForceAndTorque(:,1)= -Fy;
    ForceAndTorque(:,2)= Fz;
    ForceAndTorque(:,3)= -Fx;
    
%     ForceAndTorque(:,7)= Tx;
%     ForceAndTorque(:,8)= Tz;
%     ForceAndTorque(:,9)= Ty;

    ForceAndTorque(:,4)= 0;
    ForceAndTorque(:,5)= -0.08;
    ForceAndTorque(:,6)= 0;

    % Compensar longitudes (brazos) de los momentos
    for i=1:length(ForceAndTorque)
        if i<=length(V_OpenSim)
            M_OpenSim(i,1)=(norm(V_OpenSim(i,2:3))/norm(V_IIWA(i,2:3)))*Tx(i);
            M_OpenSim(i,2)=(norm(V_OpenSim(i,1:2:3))/norm(V_IIWA(i,1:2)))*Tz(i);
            M_OpenSim(i,3)=(norm(V_OpenSim(i,1:2))/norm(V_IIWA(i,1:2:3)))*Ty(i);
        else
            M_OpenSim(i,1)=(norm(V_OpenSim(end,2:3))/norm(V_IIWA(end,2:3)))*Tx(i);
            M_OpenSim(i,2)=(norm(V_OpenSim(end,1:2:3))/norm(V_IIWA(end,1:2)))*Tz(i);
            M_OpenSim(i,3)=(norm(V_OpenSim(end,1:2))/norm(V_IIWA(end,1:2:3)))*Ty(i);
        end
    end

    ForceAndTorque(:,7)=M_OpenSim(:,1);
    ForceAndTorque(:,8)=M_OpenSim(:,2);
    ForceAndTorque(:,9)=M_OpenSim(:,3);

else
    % Calculo FD haciendo uso de la toolbox de Matlab, EN EL SIST COORD DEL ROBOT
    [ForceAndTorque] = f_TCPForces(Datos,DatosVacio,tsample);

    % Cambio el sentido de todos los vectores para que actuen sobre el brazo
    % del paciente
    Fx=-ForceAndTorque(:,1);
    Fy=-ForceAndTorque(:,2);
    Fz=-ForceAndTorque(:,3);

    Tx=ForceAndTorque(:,7); % El sentido de los torques se trabaja a posteriori
    Ty=ForceAndTorque(:,8);
    Tz=ForceAndTorque(:,9);

    % salen con la siguiente orientaci�n de la Toolbox:
    %
    %               |----->z
    %              /|
    %             /x|y
    % orientacion de OpenSim
    %                           Quedando:
    %                  |y                Xos=-Z
    %                  | /z              Yos=-y
    %           x<-----|/                Zos=-x

    ForceAndTorque(:,1)= -1.*(Fz);%-Fy(1));
    ForceAndTorque(:,2)=-1.*(Fy);%-Fz(1));
    ForceAndTorque(:,3)= -1.*(Fx);%-Fx(1));

    ForceAndTorque(:,4)= 0;
    ForceAndTorque(:,5)= -0.08;
    ForceAndTorque(:,6)= 0;

    ForceAndTorque(:,7)= -0.001.*(Tz);%-Ty(1));
    ForceAndTorque(:,8)= -0.001.*(Ty);%-Tz(1));
    ForceAndTorque(:,9)= 0.*-1.*(Tx);%-Tx(1)); % la componente z me da igual porque el propio mango ya resbala
end

    clear Fx Fy Fz Tx Ty Tz
    %% Creo variable External Forces (FORCES AND TORQUES)

    %Guardo todos los datos en un Storage -> ExternalForcesStorage
    ExternalForcesTorquesStorage=org.opensim.modeling.Storage();
    ExternalForcesTorquesStorage.setName('ExternalLoads.mot');   %
    ExternalForcesTorquesStorage.setInDegrees(true); %Igual que en Gait2354
    % Time=TrcTableCreada.getIndependentColumn;
    %     Force=ForceAndTorque(:,1:3);
    %     Torque=ForceAndTorque(:,7:9);
    ColumnLabels=org.opensim.modeling.ArrayStr();
    ColumnLabels.append('time');
    ColumnLabels.append('hand_force_vx');
    ColumnLabels.append('hand_force_vy');
    ColumnLabels.append('hand_force_vz');
    ColumnLabels.append('hand_force_px');
    ColumnLabels.append('hand_force_py');
    ColumnLabels.append('hand_force_pz');
    ColumnLabels.append('hand_torque_x');
    ColumnLabels.append('hand_torque_y');
    ColumnLabels.append('hand_torque_z');

    ExternalForcesTorquesStorage.setColumnLabels(ColumnLabels);
    %Meto los valores COMO STATEVECTORS
    for i=1:length(stampsST)%length(t(1,:))-1
        fila=org.opensim.modeling.StateVector();
        v=org.opensim.modeling.Vector();
        v.resize(int16(length(ForceAndTorque(1,:))));
        for j = 1:length(ForceAndTorque(1,:))
            v.set(int16(j-1),ForceAndTorque(i,j)); %Vector empieza desde 0
            fila.setStates(1,v);
            fila.setTime(stampsST(i));
            %             size=fila.getSize;
        end
        ExternalForcesTorquesStorage.append(fila);
    end

    ExternalForcesTorquesStorage.print(strcat(CD_model,'\ForcesAndTorques\ExternalLoads.mot'));

    External_Force_FT=org.opensim.modeling.ExternalForce(ExternalForcesTorquesStorage,'hand_force_v','hand_force_p','hand_torque_','hand','ground','hand');

    External_Force_FT.setName('TCP_ExternalForce');
    External_Force_FT.setAppliedToBodyName('hand');        %%%%%
    % External_Force.setForceExpressedInBodyName('hand');  % No aplica en
    % el caso de que la fuerza se aplique sobre un body (Instrucciones de
    % OpenSim)
    External_Force_FT.print(strcat(CD_model,'\ForcesAndTorques\ExternalForce.xml'));

    clear ColumnLabels fila v
    %% Aplico las fuerzas en External Loads (FORCES AND TORQUES)

    External_Loads_FT=org.opensim.modeling.ExternalLoads();
    External_Loads_FT.adoptAndAppend(External_Force_FT);
    External_Loads_FT.setLowpassCutoffFrequencyForLoadKinematics(6);
    External_Loads_FT.setDataFileName('ExternalLoads.mot');
    % External_Loads_FT.setExternalLoadsModelKinematicsFileName(motFilePath); NO ES NECESARIO

    xmlExternalLoadsFileName_FT=strcat(CD_model,'\ForcesAndTorques\ExternalLoads.xml');
    External_Loads_FT.print(xmlExternalLoadsFileName_FT);
    motExternalLoadsFileName_FT=strcat(CD_model,'\ForcesAndTorques\ExternalLoads.mot');


% clear External_Force_FT External_Loads_FT
pause(1);
%% RRA - PENDIENTE DE VALIDAR
import org.opensim.modeling.*
CD_rra=strcat(CD_model,'\RRA');
%Coordenadas (todas)
CoordSet= model.getCoordinateSet();
elv_angle=CoordSet.get('elv_angle');
shoulder_elv=CoordSet.get('shoulder_elv');
shoulder_rot=CoordSet.get('shoulder_rot');
elbow_flexion=CoordSet.get('elbow_flexion');
pro_sup=CoordSet.get('pro_sup');
deviation=CoordSet.get('deviation');
flexion=CoordSet.get('flexion');
%Bloqueos:
elv_angle.set_locked(0);
shoulder_elv.set_locked(0);
shoulder_rot.set_locked(0);
elbow_flexion.set_locked(0);
pro_sup.set_locked(1);
deviation.set_locked(1);
flexion.set_locked(1);
model.print([CD_model,'\',MODELO]);

sto=org.opensim.modeling.Storage(motFilePath);
% Tiempos:
StartTime=sto.getFirstTime;
LastTime=sto.getLastTime;

rraTool=RRATool();
rraTool.setName('RRATool');
% Model
rraTool.setModel(model);
rraTool.setModelFilename(strcat(CD_model,'\',MODELO));
% Replace Force Set
rraTool.setReplaceForceSet(true);
% Set Force Set
actuatorsFile = [CD_rra, '\RRA_Actuators.xml'];
forceSetFile = org.opensim.modeling.ArrayStr();
forceSetFile.append(actuatorsFile);
rraTool.setForceSetFiles(forceSetFile);
% Results
rraTool.setResultsDir(strcat(CD_model,'\RRAResults'));
% Output precision
rraTool.setOutputPrecision(20);
% Time Range
rraTool.setStartTime(StartTime);
rraTool.setFinalTime(LastTime);
% Solve For Equilibrium
rraTool.setSolveForEquilibrium(false);
% External Loads File
rraTool.setExternalLoadsFileName(xmlExternalLoadsFileName_FT);
% Filtered Motion
rraTool.setDesiredKinematicsFileName(motFilePath);
% Tasks
rraTool.setTaskSetFileName(strcat(CD_rra,'\RRA_Tasks-ROBOESPAS_flex.xml'));
% Constraints
rraTool.setConstraintsFileName(strcat(CD_rra,'\RRA_ControlConstraints_ROBOESPAS.xml'));
%  Low Pass Frequency
rraTool.setLowpassCutoffFrequency(6);  
% Output model Name
rraTool.setOutputModelFileName(strcat(CD_model,'\',strrep(MODELO, '_calibrated.osim', '_adjusted.osim')));
%Actuators
%     rraTool.setForceSetFiles(strcat(CD_rra,'Reserve_Actuators_Roboespas.xml')); %%%%%%%
% Look ahead window time
% rraTool.setTimeWindow(0.001);
% 
% rraTool.setUseFastTarget(false);

rraTool.setAdjustedCOMBody('thorax');
rraTool.setAdjustCOMToReduceResiduals(1);

rraTool.print(strcat(CD_rra,'\setupActualRRA.xml'));

rra = RRATool(strcat(CD_rra,'\setupActualRRA.xml'));
rra.run; %Esto se hace por seguridad. Recomendaci�n de OpenSim.
% rraTool.run
disp('RRA done');

model.print(strrep(modeloPath, '_calibrated.osim', '_adjusted.osim') );
MODELO = strrep(MODELO, '_calibrated.osim', '_adjusted.osim');
%% CMC
import org.opensim.modeling.*;

% model = f_ModelCoordChanges(CD_model,MODELO);
% model.print(strcat(CD_model,'\',MODELO))

CD_cmc=strcat(CD_model,'\CMC');
%Coordenadas (todas)
CoordSet= model.getCoordinateSet();
elv_angle=CoordSet.get('elv_angle');
shoulder_elv=CoordSet.get('shoulder_elv');
shoulder_rot=CoordSet.get('shoulder_rot');
elbow_flexion=CoordSet.get('elbow_flexion');
pro_sup=CoordSet.get('pro_sup');
deviation=CoordSet.get('deviation');
flexion=CoordSet.get('flexion');
%Bloqueos:
elv_angle.set_locked(0);
shoulder_elv.set_locked(0);
shoulder_rot.set_locked(0);
elbow_flexion.set_locked(0);
pro_sup.set_locked(1);
deviation.set_locked(1);
flexion.set_locked(1);
model.print([CD_model,'\',MODELO]);

sto=org.opensim.modeling.Storage(motFilePath);
% Tiempos:
StartTime=sto.getFirstTime;
LastTime=sto.getLastTime;

% add reserve actuators and residuals
import org.opensim.modeling.*;
if ~contains(MODELO, '_withReserves')
    reserve_actuators = [CD_cmc, '\CMC_Actuators.xml'];
    % reserve_actuators = [CD_model, '\Arm_Flexion_Millard_V2_Actuators.xml'];
    force_set = org.opensim.modeling.ForceSet(reserve_actuators, true);
    force_set.setMemoryOwner(false);  % model will be the owner
    for i = 1:force_set.getSize()-1
        model.updForceSet().append(force_set.get(i));
    end
    MODELO = strrep(MODELO, '.osim', '_withReserves.osim');
    model.print([CD_model,'\',MODELO]);
end
%     cmcTool=CMCTool(strcat(CD_cmc,"\CMC_Setup_Roboespas_Flex.xml"));
cmcTool=CMCTool();
% Name
cmcTool.setName('CMCtool');
% Model
cmcTool.setModel(model);
cmcTool.setModelFilename(strcat(CD_model,'\',MODELO));
% Replace Force Set
cmcTool.setReplaceForceSet(false);
% Reserve actuators
% cmcTool.setForceSetFiles(strcat(CD_cmc,'\CMC_Reserve_Actuators.xml'));
% Results
cmcTool.setResultsDir(strcat(CD_model,'\CMCResults'));
% Output precision
cmcTool.setOutputPrecision(20);
% Time Range
cmcTool.setStartTime(StartTime);
cmcTool.setFinalTime(LastTime);
% Solve For Equilibrium
cmcTool.setSolveForEquilibrium(true);
% Maximum number of Integrator Steps
cmcTool.setMaximumNumberOfSteps(1);
% Maximum integration step size
cmcTool.setMaxDT(1e-03);
% Minimum integration step size
cmcTool.setMinDT(1e-03);
% Integrator error tolerance
cmcTool.setErrorTolerance(1e-04);
% External Loads File
cmcTool.setExternalLoadsFileName(xmlExternalLoadsFileName_FT);
% Filtered Motion
cmcTool.setDesiredKinematicsFileName(motFilePath);
% Tasks
cmcTool.setTaskSetFileName(strcat(CD_cmc,'\CMC_Tasks-ROBOESPAS_flex.xml'));
% Actuator Constraints
cmcTool.setConstraintsFileName(strcat(CD_cmc,'\CMC_ControlConstraints_ROBOESPAS2.xml'));
%  Low Pass Frequency
cmcTool.setLowpassCutoffFrequency(6);
% Look ahead window time
cmcTool.setTimeWindow(0.01);

% Fast Optimization Target. True -> mas rapido y preciso pero tiene que
% cumplir las aceleraciones. En el GUI esta puesto por defecto.
% POR EL MOMENTO NO SE PUEDE UTILIZAR DEBIDO A QUE EL MODELO OSIM UTILIZADO
% NO TIENE BIEN DEFINIDAS LAS DIN�MICAS. SI EN UN FUTURO SE DISPONE DE OTRO
% MODELO QUE CUMPLA ESTO, O SE CONSIGUEN MEJORAR ESTAS DIN�MICAS, SE DEBER�
% USAR LA OPCI�N FastTarget
cmcTool.setUseFastTarget(false);

% % Points: No es necesario
% %   cmcTool.setDesiredPointsFileName(motFilePath);

cmcTool.print(strcat(CD_cmc,'\setupActualCMC.xml'));

cmc = CMCTool(strcat(CD_cmc,'\setupActualCMC.xml'));
cmc.run; %Esto se hace por seguridad. Recomendaci�n de OpenSim.
% cmcTool.run;

disp('CMC Completado');

%% Representar excitaciones estimadas con CMC
[cmcExcitations] = f_importCMCResults(strcat(CD_cmc, 'Results\CMCtool_controls.sto'));
[cmcActivations,joints] = f_importCMCResults(strcat(CD_cmc, 'Results\CMCtool_states.sto'));
muscles = fieldnames(cmcExcitations);
numMuscles = length(muscles)-1;
f = figure('Name', 'Estimated EMG', 'WindowState', 'maximized');
for i = 1:numMuscles
    subplot(ceil(numMuscles/2),2,i, 'Parent',f);
    hold on
    plot(cmcExcitations.time, cmcExcitations.(muscles{i+1}))
    if i<8
        plot(cmcActivations.time, cmcActivations.(muscles{i+1}), 'Color', 'r')
        legend('Excitaci�n', 'Activaci�n')
    else
        legend('Control')
    end
    title(replace(muscles{i+1}, '_', ' '))
    ylim([0 1])
    drawnow
end