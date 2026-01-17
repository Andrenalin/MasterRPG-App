// © André Trettin

import Foundation

public struct RootManager: Sendable {
    public init(
        adventureRoot: any ItemRootControllable,
        audioRoot: any ItemRootControllable,
        characterRoot: any ItemRootControllable,
        diceRoot: any ItemRootControllable,
        generatorRoot: any ItemRootControllable,
        mapRoot: any ItemRootControllable,
        pdfRoot: any ItemRootControllable,
        photoRoot: any ItemRootControllable,
        spaceRoot: any ItemRootControllable,
        tableRoot: any ItemRootControllable,
        weatherRoot: any ItemRootControllable
    ) {
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.characterRoot = characterRoot
        self.diceRoot = diceRoot
        self.generatorRoot = generatorRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.weatherRoot = weatherRoot
    }

    public init(
        diceRoot: any ItemRootControllable,
        generatorRoot: any ItemRootControllable,
        pdfRoot: any ItemRootControllable,
        tableRoot: any ItemRootControllable,
    ) {
        self.diceRoot = diceRoot
        self.generatorRoot = generatorRoot
        self.pdfRoot = pdfRoot
        self.tableRoot = tableRoot
        
        self.adventureRoot = tableRoot
        self.audioRoot = tableRoot
        self.characterRoot = tableRoot
        self.mapRoot = tableRoot
        self.photoRoot = tableRoot
        self.spaceRoot = tableRoot
        self.weatherRoot = tableRoot
    }

    public let adventureRoot: ItemRootControllable
    public let audioRoot: ItemRootControllable
    public let characterRoot: ItemRootControllable
    public let diceRoot: ItemRootControllable
    public let generatorRoot: ItemRootControllable
    public let mapRoot: ItemRootControllable
    public let pdfRoot: ItemRootControllable
    public let photoRoot: ItemRootControllable
    public let spaceRoot: ItemRootControllable
    public let tableRoot: ItemRootControllable
    public let weatherRoot: ItemRootControllable
    
    public func rootModel(for module: NetworkModules) -> (any ItemRootControllable)? {
        switch module {
        case .adventure: adventureRoot
        case .audio: audioRoot
        case .value: characterRoot
        case .dice: diceRoot
        case .generator: generatorRoot
        case .map: mapRoot
        case .pdf: pdfRoot
        case .photo: photoRoot
        case .space: spaceRoot
        case .table: tableRoot
        case .weather: weatherRoot
        case .editor: nil
        case .game: nil
        case .none: nil
        case .search: nil
        case .setting: nil
        }
    }
    
    @MainActor public func itemRootController(for module: NetworkModules) -> ItemRootController? {
        rootModel(for: module)?.rootController
    }
    
    public subscript(_ module: NetworkModules) -> (any ItemRootControllable)? {
        rootModel(for: module)
    }
        
    static public func preview(fake: ItemRootControllable) -> RootManager {
        RootManager(adventureRoot: fake, audioRoot: fake, characterRoot: fake, diceRoot: fake, generatorRoot: fake, mapRoot: fake, pdfRoot: fake, photoRoot: fake, spaceRoot: fake, tableRoot: fake, weatherRoot: fake)
    }
}
