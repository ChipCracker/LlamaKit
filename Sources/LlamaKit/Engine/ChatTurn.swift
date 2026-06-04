//
//  ChatTurn.swift
//  Conversation primitives shared by the engine and chat formats.
//
import Foundation

/// A role in the chat history.
public enum ChatRole: String, Sendable {
    case system
    case user
    case assistant
}

/// One message in the conversation, used for prompt templating.
public struct ChatTurn: Sendable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}
