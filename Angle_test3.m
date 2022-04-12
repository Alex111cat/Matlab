%https://docs.exponenta.ru/comm/ug/bluetooth-low-energy-transmitter.html

clc;
clear all;

% Настройка рекламного канала PDU
cfgLLAdv = bleLLAdvertisingChannelPDUConfig;
cfgLLAdv.PDUType = 'Advertising indication';
cfgLLAdv.AdvertisingData = '0123456789ABCDEF';
cfgLLAdv.AdvertiserAddress = '1234567890AB';

% Создание рекламного канала PDU
messageBits = bleLLAdvertisingChannelPDU(cfgLLAdv);

phyMode = 'LE2M'; % Выбор одного из режимов передачи PHY {'LE1M','LE2M','LE500K','LE125K'}
sps = 8; 
channelIdx = 37; % Значение индекса канала в диапазоне от 0 до 39
accessAddLen = 32;% Длина адреса доступа (связи между двумя устройствами)
accessAddHex = '8E89BED6'; % Значение адреса доступа в шестнадцатеричном формате
accessAddBin = de2bi(hex2dec(accessAddHex),accessAddLen)'; % Адрес доступа в двоичном формате

symbolRate = 2e6;

% Создание формы сигнала
txWaveform = bleWaveformGenerator(messageBits,...
    'Mode', phyMode,...
    'SamplesPerSymbol',sps,...
    'ChannelIndex', channelIdx,...
    'AccessAddress', accessAddBin);

% Настройка спектрального сигнала
spectrumScope = dsp.SpectrumAnalyzer( ...
    'SampleRate', symbolRate*sps,...
    'SpectrumType', 'Power density', ...
    'SpectralAverages', 10, ...
    'YLimits', [-130 0], ...
    'Title', 'Baseband BLE Signal Spectrum', ...
    'YLabel', 'Power spectral density');

% Показать спектральную плотность мощности BLE сигнала
%spectrumScope(txWaveform);

% Создание файла для записи
fileID = fopen('AngleTest.txt','w');
n = 0;
while (n <= 100)
    
    % Cоздание объекта настройки для угловой оценки BLE
    cfg = bleAngleEstimateConfig('ArraySize',4); 

    %Выборки IQ в виде вектор-столбца с комплексным знаком.
    %Этот аргумент соответствует 8 μs значениям длительности паза и отчетного периода
    IQsamples = txWaveform;

    IQsamples2 = IQsamples * 0;
    k = 1;
    b = randperm(139);
    for i = 1:1536
        if mod(i, b(139)) == 0
        k = k + 1;  
        IQsamples2(k, 1) = IQsamples(i); 
        end
    end
    spectrumScope(IQsamples2(1:1536));
    %Оценка угола прибытия (AoA) или угола отбытия (AoD)
    angle = bleAngleEstimate(IQsamples2(1:k),cfg);
    % Запись значений в файл
    fprintf(fileID,'%6.3f\n',angle);
    n = n + 1;
end

% Закрытие файла
fclose(fileID);

%Чтение из файла
fileID = fopen('AngleTest.txt','r');

formatSpec = '%f';
A = fscanf(fileID,formatSpec);
V = var(A);
disp(V);

