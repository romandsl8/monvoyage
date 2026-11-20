import SwiftUI
import CoreData

@main
struct MonVoyageApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter.shared
    @StateObject private var rates = ExchangeRateService.shared
    @StateObject private var weather = WeatherService.shared
    @StateObject private var affluence = AffluenceService.shared
    @StateObject private var queueTimes = QueueTimesService.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
                .environment(\.locale, SharedLocale.fr)
                .environmentObject(router)
                .environmentObject(rates)
                .environmentObject(weather)
                .environmentObject(affluence)
                .environmentObject(queueTimes)
                .environmentObject(settings)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) {
            await BackgroundRefresh.run()
        }
    }
}
