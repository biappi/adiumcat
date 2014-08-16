//
//  main.swift
//  adiumcat
//
//  Created by Antonio Malara on 16/08/14.
//  Copyright (c) 2014 Antonio Malara. All rights reserved.
//

import Foundation

// MARK: -
// MARK: Constants and helpers
// MARK: -

let adiumBasePath = "~/Library/Application Support/Adium 2.0/Users/Default".stringByExpandingTildeInPath
let accountPlistPath = adiumBasePath.stringByAppendingPathComponent("Accounts.plist")
let fm = NSFileManager.defaultManager()

let isodateFormatter = NSDateFormatter()
isodateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"
isodateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
isodateFormatter.timeZone = NSTimeZone(forSecondsFromGMT: 0)

// MARK: -
// MARK: File mangling
// MARK: -

func logsDirs() -> [String] {
    var fullNames = [String]()
    
    let basePath = adiumBasePath.stringByAppendingPathComponent("Logs")
    let logsDirs = fm.contentsOfDirectoryAtPath(basePath, error: nil)
    
    for dir in logsDirs {
        let dirString = dir as String
        fullNames.append(basePath.stringByAppendingPathComponent(dirString))
    }
    
    return fullNames
}

func allBuddies() ->[String] {
    var allBuddies = [String]()
    
    for dir in logsDirs() {
        var error : NSError?
        
        let buddies = fm.contentsOfDirectoryAtPath(dir, error: &error) as [String]?
        
        if !error {
            for buddyDir in buddies! {
                if buddyDir != ".DS_Store" {
                    allBuddies.append(buddyDir)
                }
            }
        }
    }
    
    return sorted(allBuddies)
}

func buddyDir(buddyName : String) -> String? {
    for dir in logsDirs() {
        var error : NSError?
        
        let buddies = fm.contentsOfDirectoryAtPath(dir, error: &error) as [String]?
        
        if !error {
            for buddyDir in buddies! {
                if buddyDir == buddyName {
                    return dir.stringByAppendingPathComponent(buddyName)
                }
            }
        }
    }
    
    return nil
}

// MARK: -
// MARK: Parsing
// MARK: -

class LogEvent {
    var alias  : String
    var sender : String
    var time   : NSDate

    init(
        alias  : String,
        sender : String,
        time   : NSDate
        )
    {
            self.alias  = alias
            self.sender = sender
            self.time   = time
    }
    
    func toString() -> String {
        return "LogEvent \(alias) \(sender) \(time)"
    }
}

class StatusEvent : LogEvent {
    var type : String
    
    init(
        type   : String,
        alias  : String,
        sender : String,
        time   : NSDate
        )
    {
        self.type = type
        super.init(alias: alias, sender: sender, time: time)
    }
    
    override func toString() -> String  {
        return "[\(self.time)] *** \(self.alias) \(self.type)"
    }
}

class MessageEvent : LogEvent {
    var message : String = ""
    
    init(
        alias   : String,
        sender  : String,
        time    : NSDate
        )
    {
        super.init(alias: alias, sender: sender, time: time)
    }
    
    override func toString() -> String  {
        return "[\(self.time)] <\(self.alias)> \(self.message)"
    }
}

class LogCollectorDelegate : NSObject, NSXMLParserDelegate {
    var me : String = ""
    var events : [LogEvent] = []
    var currentMessage : MessageEvent?
    
    func parser(
        parser: NSXMLParser!,
        didStartElement elementName: String!,
        namespaceURI: String!,
        qualifiedName qName: String!,
        attributes attributeDict: [NSObject : AnyObject]!
        )
    {
        if elementName == "chat" {
            let me: AnyObject? = attributeDict["account"]
            if me {
                self.me = me as String
            }
        }

        if elementName == "status" {
            let type:   AnyObject? = attributeDict["type"]
            let alias:  AnyObject? = attributeDict["alias"]
            let sender: AnyObject? = attributeDict["sender"]
            let time:   AnyObject? = attributeDict["time"]
            
            if type && alias && sender && time {
                let date = isodateFormatter.dateFromString(time! as String)
                if date {
                    let item = StatusEvent(
                        type:   type!   as String,
                        alias:  alias!  as String,
                        sender: sender! as String,
                        time:   date!
                    )
                    
                    self.events.append(item)
                }
            }
        }
        
        if elementName == "message" {
            let alias:   AnyObject? = attributeDict["alias"]
            let sender:  AnyObject? = attributeDict["sender"]
            let time:    AnyObject? = attributeDict["time"]
            
            if alias && sender && time {
                let date = isodateFormatter.dateFromString(time! as String)
                if date {
                    let item = MessageEvent(
                        alias:   alias!  as String,
                        sender:  sender! as String,
                        time:    date!
                    )
                    
                    self.events.append(item)
                    self.currentMessage = item
                }
            }
        }
    }
    
    func parser(
        parser: NSXMLParser!,
        didEndElement elementName: String!,
        namespaceURI: String!,
        qualifiedName qName: String!
        )
    {
        if elementName == "message" {
            currentMessage = nil
        }
    }
    
    func parser(parser: NSXMLParser!, foundCharacters string: String!) {
        if self.currentMessage {
            let message = self.currentMessage!
            
            let newMessage = message.message.stringByAppendingString(string)
            message.message = newMessage
        }
    }
}

func loadAllConversations(buddyDir : String) -> [LogEvent] {
    var error : NSError?
    var allXmls = [NSURL]()
    
    let convs = fm.contentsOfDirectoryAtPath(buddyDir, error: &error) as [String]?
    if !error {
        for dayDir in convs! {
            let filePath = buddyDir.stringByAppendingPathComponent(dayDir)
            let fileName = dayDir.stringByReplacingOccurrencesOfString(".chatlog",
                withString: ".xml",
                options: NSStringCompareOptions.BackwardsSearch,
                range: nil
            )
            let path = filePath.stringByAppendingPathComponent(fileName)
            allXmls.append(NSURL(fileURLWithPath: path))
        }
    }
    
    // - //
    
    let delegate = LogCollectorDelegate()
    for file in allXmls {
        let parser = NSXMLParser(contentsOfURL: file)
        parser.delegate = delegate
        parser.parse()
    }
    
    return delegate.events
}

// MARK: -
// MARK: CLI Usage
// MARK: -

func printAllBuddies() {
    for buddy in allBuddies() {
        println(buddy)
    }
    exit(0)
}

func printBuddy(name : String) {
    let dir = buddyDir(name)
    if dir {
        let events = loadAllConversations(dir!)
        for e in events {
            println(e.toString())
        }
        exit(0)
    } else {
        println("logs for \"\(name)\" not found!")
        exit(2)
    }
}

func usage() {
    let program = Process.arguments[0]
    println("usage: \(program) [buddy_name]")
    exit(1)
}

func main() {
    let argc = countElements(Process.arguments)
    
    if argc == 1 {
        printAllBuddies()
    } else if argc == 2 {
        printBuddy(Process.arguments[1])
    } else if argc > 3 {
        usage()
    }
}

main()