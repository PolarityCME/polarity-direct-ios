//
//  ChatMsg.swift
//  PolarityDirect
//
//  Created by Wayne Russell on 2026-01-07.
//
import Foundation

struct ChatMsg: Identifiable {
    let id = UUID()
    let dir: String   // "IN" or "OUT"
    let text: String
}
