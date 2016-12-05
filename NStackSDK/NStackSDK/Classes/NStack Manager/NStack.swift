//
//  NStack.swift
//  NStack
//
//  Created by Kasper Welner on 07/09/15.
//  Copyright © 2015 Nodes. All rights reserved.
//

import Foundation
import UIKit
import Cashier

public class NStack {

    /// The singleton object which should be used to interact with NStack API.
    public static let sharedInstance = NStack()

    /// The configuration object the shared instance have been initialized with.
    public fileprivate(set) var configuration: Configuration!

    /// The manager responsible for fetching, updating and persisting translations.
    public fileprivate(set) var translationsManager: TranslationManager?

    /// The manager responsible for handling and showing version alerts and messages.
    public fileprivate(set) var alertManager: AlertManager!

    /// This gets called when the phone language has changed while app is running.
    /// At this point, translations have been updated, if there was an internet connection.
    public var languageChangedHandler: (() -> Void)?

    internal var avoidUpdateList: [UIApplicationLaunchOptionsKey] = [UIApplicationLaunchOptionsKey.location]

    internal var persistentStore: NOPersistentStore {
        return NOPersistentStore.cache(withId: NStackConstants.persistentStoreID)
    }

    internal var connectionManager: ConnectionManager!
    internal fileprivate(set) var configured = false
    internal var observer: ApplicationObserver?

    // MARK: - Start NStack -

    fileprivate init() {}

    /**
     Initializes NStack and, if `updateAutomaticallyOnStart` is set on the passed `Configuration`
     object, fetches all data (including translations if enabled) from NStack API right away.

     - parameter configuration: A `Configuration` struct containing API keys and translations type.
     - parameter launchOptions: Launch options passed from `applicationDidFinishLaunching:` func.
     */
    public class func start(configuration: Configuration,
                            launchOptions: [UIApplicationLaunchOptionsKey: Any]?) {
        sharedInstance.start(configuration: configuration, launchOptions: launchOptions)
    }

    fileprivate func start(configuration: Configuration,
                           launchOptions: [UIApplicationLaunchOptionsKey: Any]?) {
        guard !configured else {
            print("NStack is already configured. Kill the app and start it again with new configuration.")
            return
        }

        self.configuration = configuration
        self.configured = true

        // For testing purposes
        VersionUtilities.versionOverride = configuration.versionOverride

        // Setup the connection manager
        let apiConfiguration = APIConfiguration(appId: configuration.appId,
                                             restAPIKey: configuration.restAPIKey,
                                             isFlat: configuration.flat)
        connectionManager = ConnectionManager(configuration: apiConfiguration)

        // Observe if necessary
        if configuration.updateOptions.contains(.onDidBecomeActive) {
            observer = ApplicationObserver(handler: { (action) in
                guard action == .didBecomeActive else { return }

                // FIXME: Fix language accept header
                let prevAcceptLangString = self.persistentStore.object(forKey: NStackConstants.prevAcceptedLanguageKey) as? String
                self.update { error in
                    if let prevAcceptLangString = prevAcceptLangString, prevAcceptLangString != TranslationManager.acceptLanguageHeaderValueString() {
                        NStack.sharedInstance.languageChangedHandler?()
                    }
                }
            })
        }

        // Setup translations
        if let translationsClass = configuration.translationsClass {
            translationsManager = TranslationManager(translationsType: translationsClass, repository: connectionManager)

            if VersionUtilities.isVersion(VersionUtilities.currentAppVersion(),
                                          greaterThanVersion: VersionUtilities.previousAppVersion()) {
                translationsManager?.clearSavedTranslations()
            }
        }

        // Setup alert manager
        alertManager = AlertManager(repository: connectionManager)

        // Update if necessary and launch options doesn't contain a key present in avoid update list
        if configuration.updateOptions.contains(.onStart) && launchOptions?.keys.contains(where: { self.avoidUpdateList.contains($0) }) != true {
            update()
        }
    }

    /// Fetches the latest data from the NStack server and updates accordingly.
    ///
    /// - Shows appropriate notifications to the user (Update notifications, what's new, messages, rate reminders).
    /// - Updates the translation strings for current language.
    ///
    /// *Note:* By default, this is automatically invoked after *NStack.start()* has been called and subsequently on applicationDidBecomeActive.
    /// To override this behavior, see the properties on the *configuration* struct.
    ///
    /// - Parameter completion: This is run after the call has finished. 
    ///                         If *error* was nil, translation strings are up-to-date.
    public func update(_ completion: ((_ error: NStackError.Manager?) -> Void)? = nil) {
        guard configured else {
            print(NStackError.Manager.notConfigured.description)
            completion?(.notConfigured)
            return
        }

        // FIXME: Refactor

        connectionManager.postAppOpen(completion: { response in
            switch response.result {
            case .success(let JSONdata):
                guard let dictionary = JSONdata as? NSDictionary else {
                    self.print("Failure: couldn't parse response. Response data: ", JSONdata)
                    completion?(.updateFailed(reason: "Couldn't parse response dictionary."))
                    return
                }

                let wrapper = AppOpenResponse(dictionary: dictionary)
                self.print("App open response wrapper: ", wrapper)

                defer {
                    completion?(nil)
                }

                guard let appOpenResponseData = wrapper.data else { return }

                if appOpenResponseData.translate.count > 0 {
                    self.translationsManager?.setTranslationsSource(appOpenResponseData.translate)
                }

                if !self.alertManager.alreadyShowingAlert {

                    if let newVersion = appOpenResponseData.update?.newerVersion {
                        self.alertManager.showUpdateAlert(newVersion: newVersion)
                    } else if let changelog = appOpenResponseData.update?.newInThisVersion {
                        self.alertManager.showWhatsNewAlert(changelog)
                    } else if let message = appOpenResponseData.message {
                        self.alertManager.showMessage(message)
                    } else if let rateReminder = appOpenResponseData.rateReminder {
                        self.alertManager.showRateReminder(rateReminder)
                    }

                    VersionUtilities.setPreviousAppVersion(VersionUtilities.currentAppVersion())
                }

                // Get last fetched language
                if let language = wrapper.languageData?.language {
                    self.translationsManager?.lastFetchedLanguage = language
                }

                self.connectionManager.setLastUpdatedToNow()

            case let .failure(error):
                self.print("Failure: \(response.response?.description ?? "unknown error")")
                completion?(.updateFailed(reason: error.localizedDescription))
            }
        })
    }
}

//MARK: - Geography -
public extension NStack {

    /**
     Updates the list of countries stored by NStack

     - parameter completion: Optional completion block when the API call has finished.
     */
    public func updateCountries(completion: ((_ countries: [Country], _ error: Error?) -> ())? = nil) {
        connectionManager.fetchCountries { (response) in
            switch response.result {
            case .success(let data):
                self.countries = data
                completion?(data, nil)
            case .failure(let error):
                completion?([], error)
            }
        }
    }

    /// Locally stored list of countries
    public private(set) var countries: [Country]? {
        get {
            return persistentStore.serializableForKey(NStackConstants.CountriesKey)
        }
        set {
            guard let newValue = newValue else {
                persistentStore.deleteSerializableForKey(NStackConstants.CountriesKey, purgeMemoryCache: true)
                return
            }
            persistentStore.setSerializable(newValue, forKey: NStackConstants.CountriesKey)
        }
    }
}

// MARK: - Utilities -

extension NStack {
    internal func print(_ items: Any...) {
        guard configured else { return }
        if configuration.verboseMode {
            Swift.print(items)
        }
    }
}
