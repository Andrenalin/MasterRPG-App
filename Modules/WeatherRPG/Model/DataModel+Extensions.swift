// @copyright André Trettin

import CoreRPG
import CoreData
import CoreSpotlight

extension RPGWeather: CoreDataId {}
extension RPGWeatherEntry: CoreDataId {}

extension RPGWeather {
    var entriesModel: [RPGWeatherEntry] {
        get { RPGWeatherEntry.sortedArray(from: entries) }
        set { entries = NSSet(array: newValue) }
    }
}

extension RPGWeather: SpotlightIndexerAttribute {
#if !os(tvOS)
    public func attributeSet() -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.identifier = (uuid ?? UUID()).uuidString
        attributeSet.displayName = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.title = CRDT(wrappedValue: name ?? "").wrappedValue
        attributeSet.textContent = CRDT(wrappedValue: information ?? "").wrappedValue
        let convertedTags = CRDT(string: tags ?? "", defaultValue: "")
        convertedTags.wrappedValue.split(separator: ",").forEach {
            if attributeSet.keywords != nil {
                attributeSet.keywords?.append(String($0))
            } else {
                attributeSet.keywords = [String($0)]
            }
        }
        return attributeSet
    }
#endif
}
