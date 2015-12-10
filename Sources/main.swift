//  Copyright © 2015 Indragie Karunaratne. All rights reserved.

import Foundation

let ProgressBarTotalTicks = 25

enum Error: ErrorType {
    case NotEnoughArguments
    case InvalidPath(String)
    case UnableToWrite(String)
    case FailedToReadPage(String, Int)
}

typealias PDFDocument = (document: CGPDFDocumentRef, pageCount: Int, path: String)

func readPDFDocuments(paths: [String]) throws -> [PDFDocument] {
    return try paths.reduce([PDFDocument]()) { (docs, path) in
        var newDocs = docs
        let standardizedPath = (path as NSString).stringByStandardizingPath
        let URL = NSURL(fileURLWithPath: standardizedPath, isDirectory: false)
        if let doc = CGPDFDocumentCreateWithURL(URL) {
            var password = ""
            while !CGPDFDocumentUnlockWithPassword(doc, password) {
                password = String.fromCString(getpass("Enter password for \(path): ")) ?? ""
            }
            let pageCount = CGPDFDocumentGetNumberOfPages(doc)
            newDocs.append(document: doc, pageCount: pageCount, path: path)
        } else {
            throw Error.InvalidPath(path)
        }
        return newDocs
    }
}

func generateStringPadding(padding: String, length: Int) -> String {
    return (0..<length).reduce("") { (str, _) in str + padding }
}

func renderProgressBar(current current: Int, total: Int) {
    let progress = Float(current) / Float(total)
    let numberOfTicks = Int(floor(progress * Float(ProgressBarTotalTicks)))
    let numberOfSpaces = ProgressBarTotalTicks - numberOfTicks
    var percentage = "\(Int(round(progress * 100)))"
    percentage = generateStringPadding(" ", length: 3 - percentage.characters.count) + percentage
    
    var progressBar = "\r|"
    progressBar += generateStringPadding("=", length: numberOfTicks)
    progressBar += generateStringPadding(" ", length: numberOfSpaces)
    progressBar += "| \(percentage)%"
    print(progressBar, terminator: "")
}

func mergePDFDocuments(documents: [PDFDocument], outputPath: String) throws {
    let outputURL = NSURL(fileURLWithPath: outputPath)
    if let context = CGPDFContextCreateWithURL(outputURL, nil, nil) {
        let totalPages = documents.reduce(0) { $0 + $1.pageCount }
        var processedPages = 0
        for (doc, pageCount, path) in documents {
            for pageIndex in 1...pageCount {
                if let page = CGPDFDocumentGetPage(doc, pageIndex) {
                    var mediaBox = CGPDFPageGetBoxRect(page, .MediaBox)
                    CGContextBeginPage(context, &mediaBox)
                    CGContextDrawPDFPage(context, page)
                    CGContextEndPage(context)
                    processedPages += 1
                    renderProgressBar(current: processedPages, total: totalPages)
                } else {
                    throw Error.FailedToReadPage(path, pageIndex)
                }
            }
        }
        CGPDFContextClose(context)
    } else {
        throw Error.UnableToWrite(outputPath)
    }
}

extension Bool {
    init?(_ string: String) {
        let lowerCaseString = string.lowercaseString
        if lowerCaseString == "y" || lowerCaseString == "yes" {
            self = true
        } else if lowerCaseString == "n" || lowerCaseString == "no" {
            self = false
        } else {
            return nil
        }
    }
}

func readBoolean(prompt: String) -> Bool {
    var booleanValue: Bool?
    while (booleanValue == nil) {
        print(prompt + " [Y/N]: ", terminator: "")
        if let input = readLine() {
            booleanValue = Bool(input)
            if booleanValue == nil {
                fputs("Please enter 'y' or 'n'\n", stderr)
            }
        }
    }
    return booleanValue!
}

func main() throws {
    let args = Process.arguments
    if (args.count < 3) {
        throw Error.NotEnoughArguments
    }
    
    let lastIndex = args.endIndex.predecessor()
    let inputPaths = Array(args[1..<lastIndex])
    let outputPath = (args[lastIndex] as NSString).stringByStandardizingPath
    
    if NSFileManager.defaultManager().fileExistsAtPath(outputPath) {
        print("A file already exists at \"\(outputPath)\"")
        if !readBoolean("Please confirm that you want to proceed") {
            return
        }
    }
    
    typealias PDFDocument = (CGPDFDocumentRef, Int, String)
    let documents = try readPDFDocuments(inputPaths)
    try mergePDFDocuments(documents, outputPath: outputPath)
}

do {
    try main()
    print("")
} catch Error.NotEnoughArguments {
    fputs("usage: pdfcat file1 file2 ... output_file\n", stderr)
} catch Error.InvalidPath(let path) {
    print("\"\(path)\" is an invalid file path")
} catch Error.UnableToWrite(let path) {
    print("Unable to write to \"\(path)\"")
} catch Error.FailedToReadPage(let path, let pageNumber) {
    print("Unable to read page \(pageNumber) of \"\(path)\"")
}
