//
//  TextLayout+FlattenedRuns.swift
//  MasterRPG
//
//  Created by Andre Trettin on 06.07.25.
//


// @copyright André Trettin

import SwiftUI

extension Text.Layout {
    /// A helper function for easier access to all runs in a layout.
    var flattenedRuns: some RandomAccessCollection<Text.Layout.Run> {
        self.flatMap { line in
            line
        }
    }
}
