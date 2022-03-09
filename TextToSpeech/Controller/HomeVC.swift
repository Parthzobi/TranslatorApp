//
//  HomeVC.swift
//  TextToSpeech
//
//  Created by Ashfaq Shaikh on 04/03/22.
//

import UIKit
import MLKit
import McPicker
import Speech

class HomeVC: UIViewController {
    
    @IBOutlet weak var vwSource: UIView!{
        didSet{
            vwSource.layer.cornerRadius = 10
        }
    }
    @IBOutlet weak var vwDestination: UIView!{
        didSet{
            vwDestination.layer.cornerRadius = 10
        }
    }
    @IBOutlet weak var txtSource: UITextView!
    @IBOutlet weak var txtDestination: UITextView!
    @IBOutlet weak var btnRecord: UIButton!{
        didSet{
            btnRecord.layer.cornerRadius = 30.0
        }
    }
    @IBOutlet weak var btnChangeLan: UIButton!
    @IBOutlet weak var btnSource: UIButton!
    @IBOutlet weak var btnDestination: UIButton!
    @IBOutlet weak var btnSourceSpeak: UIButton!
    @IBOutlet weak var btnDestinationSpeak: UIButton!
    @IBOutlet weak var btnViewEndEventTap: UIButton!
    
    // MARK: Properties
    let ripple = Ripples()
    var translator: Translator!
    let locale = Locale.current
    lazy var allLanguages = TranslateLanguage.allLanguages().sorted {
      return locale.localizedString(forLanguageCode: $0.rawValue)!
        < locale.localizedString(forLanguageCode: $1.rawValue)!
    }
    
    private let arrSupportedLan = SFSpeechRecognizer.supportedLocales()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    let synth = AVSpeechSynthesizer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.prepareUI()
        NotificationCenter.default.addObserver(
          self, selector: #selector(remoteModelDownloadDidComplete(notification:)),
          name: .mlkitModelDownloadDidSucceed, object: nil)
        NotificationCenter.default.addObserver(
          self, selector: #selector(remoteModelDownloadDidComplete(notification:)),
          name: .mlkitModelDownloadDidFail, object: nil)
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        vwSource.dropShadow(color: .black, opacity: 0.3, offSet: CGSize(width: -1, height: 1), radius: 4, scale: true)
        vwDestination.dropShadow(color: .black, opacity: 0.3, offSet: CGSize(width: -1, height: 1), radius: 4, scale: true)
        speechRecognizer.delegate = self
        // Asynchronously make the authorization request.
        SFSpeechRecognizer.requestAuthorization { authStatus in
            // Divert to the app's main thread so that the UI
            // can be updated.
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.btnRecord.isEnabled = true
                    
                case .denied:
                    self.btnRecord.isEnabled = false
                    //self.recordButton.setTitle("User denied access to speech recognition", for: .disabled)
                    
                case .restricted:
                    self.btnRecord.isEnabled = false
                    //self.recordButton.setTitle("Speech recognition restricted on this device", for: .disabled)
                    
                case .notDetermined:
                    self.btnRecord.isEnabled = false
                    //self.recordButton.setTitle("Speech recognition not yet authorized", for: .disabled)
                    
                default:
                    self.btnRecord.isEnabled = false
                }
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ripple.position = btnRecord.center
    }

    static func instance() -> HomeVC{
        return UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "HomeVC") as! HomeVC
    }
    
    private func prepareUI(){
        synth.delegate = self
        self.btnRecord.isEnabled = false
        self.txtSource.placeholder = "Write here"
        ripple.radius = 200
        ripple.rippleCount = 5
        view.layer.addSublayer(ripple)
        let inputLanguage = allLanguages[allLanguages.firstIndex(of: TranslateLanguage.english) ?? 0]
        self.btnSource.accessibilityIdentifier = inputLanguage.rawValue
        self.setSpeechLang(inputLanguage.rawValue)
        let outputLanguage = allLanguages[allLanguages.firstIndex(of: TranslateLanguage.hindi) ?? 0]
        self.btnDestination.accessibilityIdentifier = outputLanguage.rawValue
        let options = TranslatorOptions(sourceLanguage: inputLanguage, targetLanguage: outputLanguage)
        translator = Translator.translator(options: options)
        self.translate()
    }
    
    private func setSpeechLang(_ inputLanguage: String){
        let combinedResult = arrSupportedLan.filter({ $0.identifier.contains("\(inputLanguage)-\(self.locale.regionCode ?? "")")})
        combinedResult.forEach { local in
            if let index = arrSupportedLan.firstIndex(of: local){
                self.speechRecognizer = SFSpeechRecognizer(locale: arrSupportedLan[index])!
            }
        }
    }
    
    @objc
    func remoteModelDownloadDidComplete(notification: NSNotification) {
        let userInfo = notification.userInfo!
        guard
            let remoteModel =
                userInfo[ModelDownloadUserInfoKey.remoteModel.rawValue] as? TranslateRemoteModel
        else {
            return
        }
        weak var weakSelf = self
        DispatchQueue.main.async {
            guard weakSelf != nil else {
                print("Self is nil!")
                return
            }
            let languageName = Locale.current.localizedString(
                forLanguageCode: remoteModel.language.rawValue)!
            if notification.name == .mlkitModelDownloadDidSucceed {
                print("Download succeeded for \(languageName)")
            } else {
                print("Download failed for \(languageName)")
            }
        }
    }
    
    @IBAction func btnRecordTap(_ sender: UIButton){
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            btnRecord.isEnabled = false
            btnViewEndEventTap.isHidden = true
            //recordButton.setTitle("Stopping", for: .disabled)
            btnRecord.setImage(UIImage.init(systemName: "mic.fill"), for: .normal)
            if ripple.isAnimating{
                ripple.stop()
            }else{
                ripple.start()
            }
        } else {
            do {
                try startRecording()
                //recordButton.setTitle("Stop Recording", for: [])
                btnViewEndEventTap.isHidden = false
                btnRecord.setImage(UIImage.init(systemName: "stop.fill"), for: .normal)
                if ripple.isAnimating{
                    ripple.stop()
                }else{
                    ripple.start()
                }
            } catch {
                //recordButton.setTitle("Recording Not Available", for: [])
                btnRecord.setImage(UIImage.init(systemName: "mic.fill"), for: .normal)
            }
        }
    }
    
    @IBAction func didTapSwap() {
        (self.txtSource.placeholder , self.txtDestination.placeholder) = (self.txtDestination.placeholder , self.txtSource.placeholder)
        (self.btnSource.accessibilityIdentifier, self.btnDestination.accessibilityIdentifier) = (self.btnDestination.accessibilityIdentifier, self.btnSource.accessibilityIdentifier)
        self.txtSource.text = self.txtDestination.text
        //+ " \u{25BE}"
        let oldbtn = self.btnSource.currentTitle ?? ""
        //+ " \u{25BE}"
        self.btnSource.setTitle(btnDestination.currentTitle ?? "", for: .normal)
        self.btnDestination.setTitle(oldbtn, for: .normal)
        let inputLanguage = TranslateLanguage.init(rawValue: self.btnSource.accessibilityIdentifier ?? TranslateLanguage.english.rawValue)
        self.setSpeechLang(inputLanguage.rawValue)
        let outputLanguage = TranslateLanguage.init(rawValue: self.btnDestination.accessibilityIdentifier ?? TranslateLanguage.english.rawValue)
        let options = TranslatorOptions(sourceLanguage: inputLanguage, targetLanguage: outputLanguage)
        translator = Translator.translator(options: options)
        self.translate()
    }
    
    @IBAction func btnSource(_ sender: UIButton){
        let arr = self.allLanguages.map({ Locale.current.localizedString(forLanguageCode: $0.rawValue) ?? "" })
        let data: [[String]] = [arr]
        McPicker.showAsPopover(data:data, fromViewController: self, sourceView: sender, doneHandler: { [weak self] (selections: [Int : String]) -> Void in
            if let name = selections[0] {
                self?.btnSource.setTitle(name, for: .normal)
                self?.btnSource.accessibilityIdentifier = self?.allLanguages[arr.firstIndex(of: name) ?? 0].rawValue
                self?.changeTranslateOption()
                self?.setSpeechLang(self?.btnSource.accessibilityIdentifier ?? TranslateLanguage.english.rawValue)
            }
        }, cancelHandler: { () -> Void in
            print("Canceled Popover")
        }, selectionChangedHandler: { (selections: [Int:String], componentThatChanged: Int) -> Void  in
            //let newSelection = selections[componentThatChanged] ?? "Failed to get new selection!"
            //print("Component \(componentThatChanged) changed value to \(newSelection)")
        })
    }
    
    @IBAction func btnDestination(_ sender: UIButton){
        let arr = self.allLanguages.map({ Locale.current.localizedString(forLanguageCode: $0.rawValue) ?? "" })
        let data: [[String]] = [arr]
        McPicker.showAsPopover(data:data, fromViewController: self, sourceView: sender, doneHandler: { [weak self] (selections: [Int : String]) -> Void in
            if let name = selections[0] {
                self?.btnDestination.setTitle(name, for: .normal)
                self?.btnDestination.accessibilityIdentifier = self?.allLanguages[arr.firstIndex(of: name) ?? 0].rawValue
                self?.changeTranslateOption()
            }
        }, cancelHandler: { () -> Void in
            print("Canceled Popover")
        }, selectionChangedHandler: { (selections: [Int:String], componentThatChanged: Int) -> Void  in
            //let newSelection = selections[componentThatChanged] ?? "Failed to get new selection!"
            //print("Component \(componentThatChanged) changed value to \(newSelection)")
        })
    }
    
    @IBAction func btnSourceSpeak(_ sender: UIButton){
        guard sender.isEnabled == true else { return }
        guard let text = self.txtSource.text else { return }
        self.readText(text)
    }
    
    @IBAction func btnDestinationSpeak(_ sender: UIButton){
        guard sender.isEnabled == true else { return }
        guard let text = self.txtDestination.text else { return }
        self.readText(text)
    }
    
    @IBAction func btnCopySource(_ sender: UIButton){
        guard let text = self.txtSource.text else { return }
        UIPasteboard.general.string = text
    }
    
    @IBAction func btnCopyDestination(_ sender: UIButton){
        guard let text = self.txtDestination.text else { return }
        UIPasteboard.general.string = text
    }
    
    @IBAction func btnDeleteSource(_ sender: UIButton){
        self.txtSource.text = nil
        self.txtDestination.text = nil
    }
    
    @IBAction func btnViewEndEventTap(_ sender: UIButton){
        sender.isHidden = true
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            btnRecord.isEnabled = false
            //recordButton.setTitle("Stopping", for: .disabled)
            btnRecord.setImage(UIImage.init(systemName: "mic.fill"), for: .normal)
            if ripple.isAnimating{
                ripple.stop()
            }else{
                ripple.start()
            }
        }
    }
    
    func model(forLanguage: TranslateLanguage) -> TranslateRemoteModel {
      return TranslateRemoteModel.translateRemoteModel(language: forLanguage)
    }

    func isLanguageDownloaded(_ language: TranslateLanguage) -> Bool {
      let model = self.model(forLanguage: language)
      let modelManager = ModelManager.modelManager()
      return modelManager.isModelDownloaded(model)
    }
    
    func changeTranslateOption(){
        let inputLanguage = TranslateLanguage.init(rawValue: self.btnSource.accessibilityIdentifier ?? TranslateLanguage.english.rawValue)
        let outputLanguage = TranslateLanguage.init(rawValue: self.btnDestination.accessibilityIdentifier ?? TranslateLanguage.english.rawValue)
        let options = TranslatorOptions(sourceLanguage: inputLanguage, targetLanguage: outputLanguage)
        self.translator = Translator.translator(options: options)
        self.translate()
    }
    
    func translate() {
      let translatorForDownloading = self.translator!

      translatorForDownloading.downloadModelIfNeeded { error in
        guard error == nil else {
          self.txtDestination.text = "Failed to ensure model downloaded with error \(error!)"
          return
        }
        if translatorForDownloading == self.translator {
            var text = ""
            if self.txtSource.text.isEmpty{
                text = self.txtSource.placeholder
            }else{
                text = self.txtSource.text ?? ""
            }
            translatorForDownloading.translate(text) { result, error in
            guard error == nil else {
              self.txtDestination.text = "Failed with error \(error!)"
              return
            }
            if translatorForDownloading == self.translator {
                if self.txtSource.text.isEmpty{
                    self.txtDestination.placeholder = result ?? ""
                }else{
                    self.txtDestination.text = result
                }
            }
          }
        }
      }
    }
    
    private func readText(_ text:String){
        if let language = NSLinguisticTagger.dominantLanguage(for: text) {
            
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSession.Category.soloAmbient)
                try audioSession.setMode(AVAudioSession.Mode.spokenAudio)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: language)
                
                //control speed and pitch
                //utterance.pitchMultiplier = 1
                //utterance.rate = 0.2
                synth.speak(utterance)
                
            } catch {
                print("audioSession properties weren't set because of an error.")
            }
        } else {
            print("Unknown language")
        }
    }
    
    private func startRecording() throws {
        
        // Cancel the previous task if it's running.
        recognitionTask?.cancel()
        self.recognitionTask = nil
        
        // Configure the audio session for the app.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode

        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object") }
        recognitionRequest.shouldReportPartialResults = true
        
        // Keep speech recognition data on device
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // Create a recognition task for the speech recognition session.
        // Keep a reference to the task so that it can be canceled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                // Update the text view with the results.
                self.txtSource.text = result.bestTranscription.formattedString
                isFinal = result.isFinal
                self.translate()
                //print("Text \(result.bestTranscription.formattedString)")
            }
            
            if error != nil || isFinal {
                // Stop recognizing speech if there is a problem.
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.btnRecord.isEnabled = true
                //self.recordButton.setTitle("Start Recording", for: [])
            }
        }

        // Configure the microphone input.
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Let the user know to start talking.
        // txtSource.text = "(Go ahead, I'm listening)"
    }

}

extension HomeVC: UITextViewDelegate{
    
    func textView(
        _ textView: UITextView, shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }
    
    func textViewDidChange(_ textView: UITextView) {
      translate()
    }
    
}

// MARK: SFSpeechRecognizerDelegate
extension HomeVC: SFSpeechRecognizerDelegate{
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            btnRecord.isEnabled = true
            //recordButton.setTitle("Start Recording", for: [])
        } else {
            btnRecord.isEnabled = false
            //recordButton.setTitle("Recognition Not Available", for: .disabled)
        }
    }
}

extension HomeVC: AVSpeechSynthesizerDelegate{
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("Start Speeck")
        self.btnSourceSpeak.isEnabled = false
        self.btnDestinationSpeak.isEnabled = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("End Speeck")
        self.btnSourceSpeak.isEnabled = true
        self.btnDestinationSpeak.isEnabled = true
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Cancel Speeck")
    }
}
