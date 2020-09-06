function [Handle] = f_HandleCoordModifications(Datos, model)
%Esta funcion permite rotar y cambiar el offset de las coordenadas
%recibidas desde el laboratorio

% Correcci�n de orientaci�n para ajustar al sist de coords de OpenSim
handle(:,1) = Datos(:,2);
handle(:,2) = Datos(:,3);
handle(:,3) = Datos(:,1);

% Posici�n inicial del marcador Handle en OpenSim
model.initSystem;
model.getMarkerSet().get(0).changeFramePreserveLocation(model.getWorkingState, model.getGround);
loc = model.getMarkerSet().get(0).get_location;
handleOpensim = [loc.get(0), loc.get(1), loc.get(2)];
model.invalidateSystem();

% Diferencia entre posici�n inicial de la trayectoria y handleOpensim
diff = handleOpensim - handle(1,:);

% Correcci�n de posici�n de toda la trayectoria del Handle
Handle = handle + diff;

end