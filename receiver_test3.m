%https://docs.exponenta.ru/comm/ug/bluetooth-low-energy-receiver.html

clc;
clear all;

phyMode = 'LE2M';
bleParam = helperBLEReceiverConfig(phyMode);

signalSource = 'ADALM-PLUTO';

if strcmp(signalSource,'File')
    switch bleParam.Mode
        case 'LE1M'
            bbFileName = 'bleCapturesLE1M.bb';
        case 'LE2M'
            bbFileName = 'bleCapturesLE2M.bb';
        case 'LE500K'
            bbFileName = 'bleCapturesLE500K.bb';
        case 'LE125K'
            bbFileName = 'bleCapturesLE125K.bb';
        otherwise
            error('Invalid PHY transmission mode. Valid entries are LE1M, LE2M, LE500K and LE125K.');
    end
    sigSrc = comm.BasebandFileReader(bbFileName);
    sigSrcInfo = info(sigSrc);
    sigSrc.SamplesPerFrame = sigSrcInfo.NumSamplesInData;
    bbSampleRate = sigSrc.SampleRate;
    bleParam.SamplesPerSymbol = bbSampleRate/bleParam.SymbolRate;

elseif strcmp(signalSource,'ADALM-PLUTO')

    % Проверка подключения радиосистемы
    if isempty(which('plutoradio.internal.getRootDir'))
        error(message('comm_demos:common:NoSupportPackage', ...
            'Communications Toolbox Support Package for ADALM-PLUTO Radio',...
            ['<a href="https://www.mathworks.com/hardware-support/' ...
            'adalm-pluto-radio.html">ADALM-PLUTO Radio Support From Communications Toolbox</a>']));
    end

    bbSampleRate = bleParam.SymbolRate * bleParam.SamplesPerSymbol;
    sigSrc = sdrrx('Pluto',...
        'RadioID',             'usb:0',...
        'CenterFrequency',     2.402e9,...
        'BasebandSampleRate',  bbSampleRate,...
        'SamplesPerFrame',     1e7,...
        'GainSource',         'Manual',...
        'Gain',                25,...
        'OutputDataType',     'double');
else
    error('Invalid signal source. Valid entries are File and ADALM-PLUTO.');
end

% Настройка спектрального сигнала
spectrumScope = dsp.SpectrumAnalyzer( ...
    'SampleRate',       bbSampleRate,...
    'SpectrumType',     'Power density', ...
    'SpectralAverages', 10, ...
    'YLimits',          [-130 -30], ...
    'Title',            'Received Baseband BLE Signal Spectrum', ...
    'YLabel',           'Power spectral density');

% Передаваемый сигнал фиксируется в виде пакета данных
dataCaptures = sigSrc();


% Визуализация спектральной плотности мощности принятого сигнала
spectrumScope(dataCaptures);

% Обработка приемника
% Инициализация объектов для обработки приемника
agc = comm.AGC('MaxPowerGain',20,'DesiredOutputPower',2);

freqCompensator = comm.CoarseFrequencyCompensator('Modulation','OQPSK', ...
    'SampleRate',bbSampleRate,...
    'SamplesPerSymbol',2*bleParam.SamplesPerSymbol,...
    'FrequencyResolution',100);

prbDet = comm.PreambleDetector(bleParam.RefSeq,'Detections','First');

% Инициализация счетчиков
pktCnt = 0;
crcCnt = 0;
displayFlag = false; % true - если полученные данные должны быть напечатаны
counter = 0;

% Цикл для декодирования полученных пакетов BLE
while length(dataCaptures) > bleParam.MinimumPacketLen

    % Необходимо рассмотреть два кадра из полученного сигнала
    % для каждой итерации.
    startIndex = 1;
    endIndex = min(length(dataCaptures),2*bleParam.FrameLength);
    rcvSig = dataCaptures(startIndex:endIndex);

    rcvAGC = agc(rcvSig); % выполнение АРУ
    rcvDCFree = rcvAGC - mean(rcvAGC); % удаление смещения постоянного тока
    rcvFreqComp = freqCompensator(rcvDCFree); % Оценка смещения несущей частоты
    rcvFilt = conv(rcvFreqComp,bleParam.h,'same'); % Выполнение гауссовской фильтрации

    % Выполнение кадровой (временной) синхронизации
    [~, dtMt] = prbDet(rcvFilt);
    release(prbDet)
    prbDet.Threshold = max(dtMt);
    prbIdx = prbDet(rcvFilt);

    % Извлечение информацию о сообщении
    [cfgLLAdv,pktCnt,crcCnt,remStartIdx] = helperBLEPhyBitRecover(rcvFilt,...
        prbIdx,pktCnt,crcCnt,bleParam);
    counter = counter + 1;

    % Оставшийся пакет данных
    dataCaptures = dataCaptures(1+remStartIdx:end);

    % Отображение декодированной информации
    if displayFlag && ~isempty(cfgLLAdv)
        fprintf('Advertising PDU Type: %s\n',cfgLLAdv.PDUType);
        fprintf('Advertising Address: %s\n',cfgLLAdv.AdvertiserAddress);
    end

    % освобождение системных объектов
    release(freqCompensator)
    release(prbDet)
end

% освобождение источника сигнала
release(sigSrc)

% Расчет ПКО
if pktCnt
    per = 1-(crcCnt/pktCnt);
    fprintf('Packet error rate for %s mode is %f.\n',bleParam.Mode,per);
else
    fprintf('\n No BLE packets were detected.\n')
end