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
spectrumScope(txWaveform);


% Обработка передатчика
% Инициализация параметров, необходимых для источника сигнала
txCenterFrequency       = 2.402e9; 
txFrameLength           = length(txWaveform);
txNumberOfFrames        = 1e4;
txFrontEndSampleRate    = symbolRate*sps;

% Если необходим вывод в файл
signalSink = 'File';

if strcmp(signalSink,'File')

    sigSink = comm.BasebandFileWriter('CenterFrequency',txCenterFrequency,...
        'Filename','bleCaptures.bb',...
        'SampleRate',txFrontEndSampleRate);
    sigSink(txWaveform); % Запись в файл основной полосы частот 'bleCaptures.bb'

elseif strcmp(signalSink,'ADALM-PLUTO')

    % Проверка подключения радиосистемы
    if isempty(which('plutoradio.internal.getRootDir'))
        error(message('comm_demos:common:NoSupportPackage', ...
                      'Communications Toolbox Support Package for ADALM-PLUTO Radio',...
                      ['<a href="https://www.mathworks.com/hardware-support/' ...
                      'adalm-pluto-radio.html">ADALM-PLUTO Radio Support From Communications Toolbox</a>']));
    end
    % Подключение радио ADALM-PLUTO к MATLAB
    connectedRadios = findPlutoRadio;
    radioID = connectedRadios(1).RadioID;
    sigSink = sdrtx( 'Pluto',...
        'RadioID',           'usb:0',...
        'CenterFrequency',   txCenterFrequency,...
        'Gain',              0,...
        'SamplesPerFrame',   txFrameLength,...
        'BasebandSampleRate',txFrontEndSampleRate);
    currentFrame = 1;
    try
        while currentFrame <= txNumberOfFrames
            % Передача данных
            sigSink(txWaveform);
            % Увеличение счетчика
            currentFrame = currentFrame + 1;
        end
    catch ME
        release(sigSink);
        rethrow(ME)
    end
else
    error('Invalid signal sink. Valid entries are File and ADALM-PLUTO.');
end

% Release the signal sink
release(sigSink)