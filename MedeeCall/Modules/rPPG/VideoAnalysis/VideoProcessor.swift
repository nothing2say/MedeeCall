//
//  VideoProcessor.swift
//  MedeeCall
//
//  Created by Nothing2saY on 2/1/21.
//

import Foundation
import Charts

enum CameraState {
    case stopped
    case running
    case paused
}

enum HeartRateSeries {
    case rawData
    case filteredData
    case fftData
    case filteredICAData
    case fftICAData
}

class VideoProcessor: NSObject, OpenCVWrapperDelegate{
    
    var videoView:VideoView? = nil
    var parent:LiveVitalView?
    var dataView: LiveVitalView?
    var cameraRunning = CameraState.stopped;
    let openCVWrapper = OpenCVWrapper()
    var heartRateCalculation:PulseCalculation?

    func frameAvailable(_ frame: UIImage, _ heartRateProgress: Float, _ frameNumber: Int32) {
        videoView?.videoFrame = frame
        parent!.progressBarValue = CGFloat(heartRateProgress)
        parent!.frameNumberLabel = NSString(format: " Frame: %d", frameNumber) as String
        
    }
    
    func framesReady(_ videoProcessingPaused: Bool, _ actualFPS:Double) {
        let actualFPSStr = NSString(format: ". Actual FPS: %.1f", actualFPS) as String
        print("ViewController: framesReady videoProcessingPaused: ", videoProcessingPaused, actualFPSStr)
        if( videoProcessingPaused){
            let pauseBetweenSamples = VideoSettings.getPauseBetweenSamples()
            if( pauseBetweenSamples ){
                cameraRunning = CameraState.paused
                parent!.startStopVideoButton = "Resume"
            }else{
                openCVWrapper.resumeCamera(Int32(VideoSettings.getFramesPerHeartRateSample()));
            }
            heartRateCalculation!.calculateHeartRate( actualFPS )
            //var heartRateStr:String = "Heart Rate: --"
            var pulseRateStr: String = "--"
            var pulseRateICAStr: String = "--"
            let hrFrequency = calculateHeartRate()
            if( hrFrequency > 0) {
                let hrFrequencyICA = calculateHeartRateFromICA()
                pulseRateStr = NSString(format: "%.0f", hrFrequency) as String
                pulseRateICAStr = NSString(format: "%.0f", hrFrequencyICA) as String
            }
            //parent!.heartRateLabel = heartRateStr
            parent?.pulseRateLabel = pulseRateStr
            parent?.pulseRateICA = pulseRateICAStr
            updateRawChart()
            updateFilteredChart()
            updateFFTChart()
            updateFilteredICAChart()
            updateFFTICAChart()
        }
    }
    func updateRawChart(){
        updateWaveform(lineChartView: parent?.lineChartsRaw, dataSeries: HeartRateSeries.rawData, "Raw RGB")
    }
    func updateFilteredChart(){
        updateWaveform(lineChartView: parent?.lineChartsFiltered, dataSeries: HeartRateSeries.filteredData, "Filtered RGB")
    }
    func updateFFTChart(){
        updateFFT(barChartView: parent?.barChartsFFT, dataSeries: HeartRateSeries.fftData, "FFT of filtered data")
    }

    func updateFilteredICAChart(){
        updateWaveform(lineChartView: parent?.lineChartsFilteredICA, dataSeries: HeartRateSeries.filteredICAData, "Filtered (ICA) RGB")
    }
    func updateFFTICAChart(){
        updateFFT(barChartView: parent?.barChartsFFTICA, dataSeries: HeartRateSeries.fftICAData, "FFT of ICA data")
    }
    
    func startStopCamera(){
        if( cameraRunning == CameraState.stopped ){
            cameraRunning = CameraState.running;
            openCVWrapper.startCamera(Int32(VideoSettings.getFrameRate()));
            parent!.startStopVideoButton = "🛑 Stop"
        }else if( cameraRunning == CameraState.running ){
            cameraRunning = CameraState.stopped;
            openCVWrapper.stopCamera();
            parent!.startStopVideoButton = "Start 🙂"
        }else if( cameraRunning == CameraState.paused ){
            cameraRunning = CameraState.running;
            openCVWrapper.resumeCamera( Int32(VideoSettings.getFramesPerHeartRateSample()));
            parent!.startStopVideoButton = "🛑 Stop"
        }

    }
    func initialize( parent:LiveVitalView){
        openCVWrapper.delegate = self
        heartRateCalculation = PulseCalculation( openCVWrapper )
        self.parent = parent
        openCVWrapper.initializeCamera(Int32(VideoSettings.getFramesPerHeartRateSample()), Int32(VideoSettings.getFrameRate()))
    }

    private func calculateHeartRate() -> Double{
        return heartRateCalculation!.heartRateFrequency! * 60.0
    }
    private func calculateHeartRateFromICA() -> Double{
        return heartRateCalculation!.heartRateFrequencyICA! * 60.0
    }

    private func updateWaveform( lineChartView:LineCharts?, dataSeries:HeartRateSeries, _ description:String){
        if let lineChart = lineChartView?.lineChart {
            let (red, green, blue) = getRDBdata(dataSeries )
            let (redPeak, greenPeak, bluePeak) = getRDBPeakHeartRate(dataSeries)
            
            if let timeSeries = heartRateCalculation!.timeSeries {
                let data = LineChartData()
                if let redData = red  {
                    addLine(data, redData, timeSeries, color:[NSUIColor.red], formatPeakData( redPeak))
                }
                if let greenData = green {
                    addLine(data, greenData, timeSeries, color:[NSUIColor.green], formatPeakData( greenPeak))

                }
                if let blueData = blue {
                    addLine(data, blueData, timeSeries, color:[NSUIColor.blue], formatPeakData( bluePeak))
                }
                if dataSeries == HeartRateSeries.filteredData {
                    if let greenMax = heartRateCalculation?.maxGreenPeaks {
                        addMaxLine( data, greenMax, color:[NSUIColor.darkGray], "Green Max")
                    }
                }else if dataSeries == HeartRateSeries.filteredICAData {
                    if let greenMax = heartRateCalculation?.ICAmaxGreenPeaks {
                        addMaxLine( data, greenMax, color:[NSUIColor.darkGray], "Green Max")
                    }
                }

                lineChart.data = data
                lineChart.chartDescription.text = description
                lineChart.chartDescription.font = .systemFont(ofSize: 16, weight: .light)
            }
        }
    }

    private func addMaxLine( _ lineChartData:LineChartData, _ maxSeries:[(Double, Double)], color:[NSUIColor], _ name:String ){
        var lineChartEntry  = [ChartDataEntry]()
        for i in 0..<maxSeries.count {
            let (yVal,xVal) = maxSeries[i]
            let value = ChartDataEntry(x: xVal, y: yVal)
            lineChartEntry.append(value)
        }

        let line = LineChartDataSet(entries: lineChartEntry, label: name)
        line.drawCirclesEnabled = true
        line.colors = color
        //lineChartData.addDataSet(line)
        lineChartData.append(line)
    

    }
    
    private func addLine( _ lineChartData:LineChartData, _ yData:[Double], _ xData:[Double], color:[NSUIColor], _ name:String) {
        var lineChartEntry  = [ChartDataEntry]() //this is the Array that will eventually be displayed on the graph.
        let count = xData.count < yData.count ? xData.count : yData.count
        for i in 0..<count {
            let value = ChartDataEntry(x: xData[i], y: yData[i])
            lineChartEntry.append(value) // here we add it to the data set
        }

        let line1 = LineChartDataSet(entries: lineChartEntry, label: name) //Here we convert lineChartEntry to a LineChartDataSet
        line1.drawCirclesEnabled = false
        line1.colors = color
        //lineChartData.addDataSet(line1) //Adds the line to the dataSet
        lineChartData.append(line1)

    }
    
    private func updateFFT( barChartView:BarCharts?, dataSeries:HeartRateSeries, _ description:String ){
        if let barChart = barChartView?.barChart {
            let (red, green, blue) = getRDBdata(dataSeries )
            
            if let timeSeries = heartRateCalculation!.FFTRedFrequency {
                if( timeSeries.count > 0){
                    let timeWidth = timeSeries[timeSeries.count-1] - timeSeries[0]; // total X time
                    let groupWidth = timeWidth/Double(timeSeries.count)
                    let groupSpace = groupWidth/4.0
                    let barSpace = groupWidth/8.0
                    let barWidth = groupWidth/8.0
                    // (barSpace + barWidth) * 3 + groupSpace= groupWidth

                    let data = BarChartData()
                    data.barWidth = barWidth
                    var hrRed = heartRateCalculation!.heartRateRedFrequency!
                    var hrGreen = heartRateCalculation!.heartRateGreenFrequency!
                    var hrBlue = heartRateCalculation!.heartRateBlueFrequency!
                    if( dataSeries == HeartRateSeries.fftICAData){
                        hrRed = heartRateCalculation!.ICAheartRateRedFrequency!
                        hrGreen = heartRateCalculation!.ICAheartRateGreenFrequency!
                        hrBlue = heartRateCalculation!.ICAheartRateBlueFrequency!
                    }
                    let redFreq = NSString(format: "Red BPM %.1f", (hrRed * 60))
                    let greenFreq = NSString(format: "Green BPM %.1f", (hrGreen * 60))
                    let blueFreq = NSString(format: "Blue BPM %.1f", (hrBlue * 60))
                    
                    if let redData = red  {
                        addBar(data, redData, timeSeries, color:[NSUIColor.red], redFreq as String)
                    }
                    if let greenData = green {
                        addBar(data, greenData, timeSeries, color:[NSUIColor.green], greenFreq as String)
                    }
                    if let blueData = blue {
                        addBar(data, blueData, timeSeries, color:[NSUIColor.blue], blueFreq as String)
                    }

                    barChart.xAxis.axisMinimum = timeSeries[0];
                    barChart.xAxis.axisMaximum = timeSeries[timeSeries.count-1]
                    
                    data.groupBars(fromX: timeSeries[0], groupSpace:groupSpace, barSpace: barSpace)
                    data.setValueFont(.systemFont(ofSize: 0, weight: .light))
                    
                    barChart.data = data
                    barChart.chartDescription.text = description
                    barChart.chartDescription.font = .systemFont(ofSize: 16, weight: .light)
                    barChart.legend.font = .systemFont(ofSize: 16, weight: .light)
                }
           }
        }
    }

    private func addBar( _ barChartData:BarChartData, _ yData:[Double], _ xData:[Double], color:[NSUIColor], _ name:String) {
        var barChartEntry  = [BarChartDataEntry]()
        for i in 0..<yData.count {
            let value = BarChartDataEntry(x: xData[i], y: yData[i]) // here we set the X and Y status in a data chart entry
            barChartEntry.append(value)
        }

        let bar1 = BarChartDataSet(entries: barChartEntry, label: name)
        bar1.colors = color
        bar1.drawValuesEnabled = false
        //barChartData.addDataSet(bar1)
        barChartData.append(bar1)
    }

    private func getRDBdata( _ dataSeries:HeartRateSeries ) -> ([Double]?, [Double]?, [Double]?){
        
        switch dataSeries {
        case .rawData:
//            return (heartRateCalculation!.deltaRawRed, heartRateCalculation!.deltaRawGreen, heartRateCalculation!.deltaRawBlue)
            return (heartRateCalculation!.rawRedPixels, heartRateCalculation!.rawGreenPixels, heartRateCalculation!.rawBluePixels)
//            return (heartRateCalculation!.normalizedRedAmplitude, heartRateCalculation!.normalizedGreenAmplitude, heartRateCalculation!.normalizedBlueAmplitude)

        case .filteredData:
            return (heartRateCalculation!.filteredRedAmplitude, heartRateCalculation!.filteredGreenAmplitude, heartRateCalculation!.filteredBlueAmplitude)

        case .fftData:
            return (heartRateCalculation!.FFTRedAmplitude, heartRateCalculation!.FFTGreenAmplitude, heartRateCalculation!.FFTBlueAmplitude)

        case .filteredICAData:
            return (heartRateCalculation!.ICARedAmplitude, heartRateCalculation!.ICAGreenAmplitude, heartRateCalculation!.ICABlueAmplitude)

        case .fftICAData:
            return (heartRateCalculation!.ICAFFTRedAmplitude, heartRateCalculation!.ICAFFTGreenAmplitude, heartRateCalculation!.ICAFFTBlueAmplitude)


        default:
            return ([Double](), [Double](), [Double]())
        }
    }
    private func getRDBPeakHeartRate( _ dataSeries:HeartRateSeries ) -> ((Double, Double)?, (Double, Double)?, (Double, Double)?){
        let peakHeartRatedata = ((0.0, 0.0), (0.0, 0.0), (0.0, 0.0))
        switch dataSeries {
            case .filteredData:
                return (heartRateCalculation!.heartRatePeakRed, heartRateCalculation!.heartRatePeakGreen, heartRateCalculation!.heartRatePeakBlue)
            case .filteredICAData:
                return (heartRateCalculation!.ICAheartRatePeakRed, heartRateCalculation!.ICAheartRatePeakGreen, heartRateCalculation!.ICAheartRatePeakBlue)
            default:
                return peakHeartRatedata
        }
    }
    private func formatPeakData( _ peakData:(Double, Double)? ) ->String {
        if let (heartRateHz, stdDeviationHz) = peakData {
            if( heartRateHz > 0.0){
                return NSString(format: "%.1f +/- %.1f", heartRateHz * 60, stdDeviationHz * 60) as String
            }
        }
        return "--"
    }
}

