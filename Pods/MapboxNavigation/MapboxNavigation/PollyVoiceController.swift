import Foundation
import AWSPolly
import AVFoundation
import MapboxCoreNavigation
import CoreLocation

/**
 `PollyVoiceController` extends the default `RouteVoiceController` by providing support for AWSPolly. `RouteVoiceController` will be used as a fallback during poor network conditions.
 */
@objc(MBPollyVoiceController)
public class PollyVoiceController: RouteVoiceController {
    
    /**
     Forces Polly voice to always be of specified type. If not set, a localized voice will be used.
     */
    public var globalVoiceId: AWSPollyVoiceId?
    
    /**
     `regionType` specifies what AWS region to use for Polly.
     */
    public var regionType: AWSRegionType = .USEast1
    
    /**
     `identityPoolId` is a required value for using AWS Polly voice instead of iOS's built in AVSpeechSynthesizer.
     You can get a token here: http://docs.aws.amazon.com/mobile/sdkforios/developerguide/cognito-auth-aws-identity-for-ios.html
     */
    public var identityPoolId: String
    
    /**
     Number of seconds a Polly request can wait before it is canceled and the default speech synthesizer speaks the instruction.
     */
    public var timeoutIntervalForRequest:TimeInterval = 2
    
    /**
     Number of steps ahead of the current step to cache spoken instructions.
     */
    public var stepsAheadToCache: Int = 3
    
    var pollyTask: URLSessionDataTask?
    
    let sessionConfiguration = URLSessionConfiguration.default
    var urlSession: URLSession
    
    var cacheURLSession: URLSession
    var cachePollyTask: URLSessionDataTask?
    
    var spokenInstructionsForRoute = NSCache<NSString, NSData>()
    
    public init(identityPoolId: String) {
        self.identityPoolId = identityPoolId
        
        spokenInstructionsForRoute.countLimit = 200
        
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType: regionType, identityPoolId: identityPoolId)
        let configuration = AWSServiceConfiguration(region: regionType, credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        sessionConfiguration.timeoutIntervalForRequest = timeoutIntervalForRequest;
        urlSession = URLSession(configuration: sessionConfiguration)
        cacheURLSession = URLSession(configuration: URLSessionConfiguration.default)
        
        super.init()
    }
    
    public override func didPassSpokenInstructionPoint(notification: NSNotification) {
        guard shouldSpeak(for: notification) == true else { return }
        
        let routeProgresss = notification.userInfo![MBRouteControllerDidPassSpokenInstructionPointRouteProgressKey] as! RouteProgress
        guard let instruction = routeProgresss.currentLegProgress.currentStepProgress.currentSpokenInstruction?.ssmlText else { return }
        
        pollyTask?.cancel()
        audioPlayer?.stop()
        startAnnouncementTimer()
        
        for (stepIndex, step) in routeProgresss.currentLegProgress.leg.steps.suffix(from: routeProgresss.currentLegProgress.stepIndex).enumerated() {
            let adjustedStepIndex = stepIndex + routeProgresss.currentLegProgress.stepIndex
            
            guard adjustedStepIndex < routeProgresss.currentLegProgress.stepIndex + stepsAheadToCache else { continue }
            guard let instructions = step.instructionsSpokenAlongStep else { continue }
            
            for instruction in instructions {
                guard spokenInstructionsForRoute.object(forKey: instruction.ssmlText as NSString) == nil else { continue }
                
                cacheSpokenInstruction(instruction: instruction.ssmlText)
            }
        }
        
        guard spokenInstructionsForRoute.object(forKey: instruction as NSString) == nil else {
            play(spokenInstructionsForRoute.object(forKey: instruction as NSString)! as Data)
            return
        }
        
        speak(instruction, error: nil)
    }
    
    func pollyURL(for instruction: String) ->  AWSPollySynthesizeSpeechURLBuilderRequest {
        let input = AWSPollySynthesizeSpeechURLBuilderRequest()
        input.textType = .ssml
        input.outputFormat = .mp3
        
        let langs = Locale.preferredLocalLanguageCountryCode.components(separatedBy: "-")
        let langCode = langs[0]
        var countryCode = ""
        if langs.count > 1 {
            countryCode = langs[1]
        }
        
        switch (langCode, countryCode) {
        case ("de", _):
            input.voiceId = .marlene
        case ("en", "CA"):
            input.voiceId = .joanna
        case ("en", "GB"):
            input.voiceId = .brian
        case ("en", "AU"):
            input.voiceId = .nicole
        case ("en", "IN"):
            input.voiceId = .raveena
        case ("en", _):
            input.voiceId = .joanna
        case ("es", "ES"):
            input.voiceId = .enrique
        case ("es", _):
            input.voiceId = .miguel
        case ("fr", _):
            input.voiceId = .celine
        case ("it", _):
            input.voiceId = .giorgio
        case ("nl", _):
            input.voiceId = .lotte
        case ("ro", _):
            input.voiceId = .carmen
        case ("ru", _):
            input.voiceId = .maxim
        case ("sv", _):
            input.voiceId = .astrid
        case ("tr", _):
            input.voiceId = .filiz
        default:
            input.voiceId = .joanna
        }
        
        if let voiceId = globalVoiceId {
            input.voiceId = voiceId
        }
        
        input.text = instruction
        
        return input
    }
    
    override func speak(_ text: String, error: String?) {
        assert(!text.isEmpty)
        
        let input = pollyURL(for: text)
        
        let builder = AWSPollySynthesizeSpeechURLBuilder.default().getPreSignedURL(input)
        builder.continueWith { [weak self] (awsTask: AWSTask<NSURL>) -> Any? in
            guard let strongSelf = self else {
                return nil
            }
            
            strongSelf.handle(awsTask)
            
            return nil
        }
    }
    
    func callSuperSpeak(_ text: String, error: String) {
        pollyTask?.cancel()
        
        guard let audioPlayer = audioPlayer else {
            super.speak(fallbackText, error: error)
            return
        }
        
        guard !audioPlayer.isPlaying else { return }
        
        super.speak(fallbackText, error: error)
    }
    
    func handle(_ awsTask: AWSTask<NSURL>) {
        guard awsTask.error == nil else {
            callSuperSpeak(fallbackText, error: awsTask.error!.localizedDescription)
            return
        }
        
        guard let url = awsTask.result else {
            callSuperSpeak(fallbackText, error: "No polly response")
            return
        }
        
        pollyTask = urlSession.dataTask(with: url as URL) { [weak self] (data, response, error) in
            guard let strongSelf = self else { return }
            
            // If the task is canceled, don't speak.
            // But if it's some sort of other error, use fallback voice.
            if let error = error as NSError?, error.code == NSURLErrorCancelled {
                return
            } else if let error = error {
                // Cannot call super in a closure
                strongSelf.callSuperSpeak(strongSelf.fallbackText, error: error.localizedDescription)
                return
            }
            
            guard let data = data else {
                strongSelf.callSuperSpeak(strongSelf.fallbackText, error: "No data")
                return
            }
            
            strongSelf.play(data)
        }
        
        pollyTask?.resume()
    }
    
    func cacheSpokenInstruction(instruction: String) {
        
        let pollyRequestURL = pollyURL(for: instruction)
        
        let builder = AWSPollySynthesizeSpeechURLBuilder.default().getPreSignedURL(pollyRequestURL)
        builder.continueWith { [weak self] (awsTask: AWSTask<NSURL>) -> Any? in
            guard let strongSelf = self else {
                return nil
            }
            
            guard let url = awsTask.result else { return nil }
            
            strongSelf.cachePollyTask = strongSelf.cacheURLSession.dataTask(with: url as URL) { (data, response, error) in
                
                if let error = error {
                    print(error.localizedDescription)
                }
                
                if let data = data {
                    strongSelf.spokenInstructionsForRoute.setObject(data as NSData, forKey: instruction as NSString)
                }
            }
            
            strongSelf.cachePollyTask?.resume()
            
            return nil
        }
    }
    
    func play(_ data: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.audioPlayer = try AVAudioPlayer(data: data)
                let prepared = self.audioPlayer?.prepareToPlay() ?? false
                
                guard prepared else {
                    self.callSuperSpeak(self.fallbackText, error: "Audio player failed to prepare")
                    return
                }
                
                self.audioPlayer?.delegate = self
                try super.duckAudio()
                let played = self.audioPlayer?.play() ?? false
                
                guard played else {
                    self.callSuperSpeak(self.fallbackText, error: "Audio player failed to play")
                    return
                }
                
            } catch  let error as NSError {
                self.callSuperSpeak(self.fallbackText, error: error.localizedDescription)
            }
        }
    }
}
