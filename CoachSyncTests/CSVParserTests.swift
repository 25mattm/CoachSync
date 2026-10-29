import XCTest
@testable import CoachSync

/// CSV roster import: decoding the encodings spreadsheet apps actually save, quoted line breaks,
/// short-year dates, and guardian emails the backend would reject.
final class CSVParserTests: XCTestCase {

    private let header = "FirstName,LastName,DateOfBirth,GuardianName,GuardianPhone,GuardianEmail,Gender\n"

    // MARK: - Decoding

    func testDecodesUTF8() {
        let text = CSVParser.decode(Data("Zoé,Léger\n".utf8))
        XCTAssertEqual(text, "Zoé,Léger\n")
    }

    func testDecodesExcelWindows1252AccentedNames() {
        // "Léger" as Excel's "CSV (Comma delimited)" saves it: é = 0xE9, which is invalid UTF-8.
        let bytes = Data([0x4C, 0xE9, 0x67, 0x65, 0x72])
        XCTAssertNil(String(data: bytes, encoding: .utf8), "precondition: not valid UTF-8")
        XCTAssertEqual(CSVParser.decode(bytes), "Léger")
    }

    func testDecodesUTF16OnlyWithAByteOrderMark() {
        var bytes = Data([0xFF, 0xFE])
        bytes.append("Ava".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(CSVParser.decode(bytes), "Ava")
    }

    // MARK: - Records

    func testQuotedLineBreakStaysInOneRecord() {
        let csv = header + "Ava,Smith,01/02/2015,\"Jane\nSmith\",555-0100,,F\n"
        let result = CSVParser.parse(csv)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.athletes.count, 1)
        XCTAssertEqual(result.athletes.first?.guardianName, "Jane\nSmith")
        XCTAssertEqual(result.athletes.first?.gender, .female)
    }

    func testQuotedCommaAndEscapedQuoteStayInOneField() {
        let csv = header + "Ava,Smith,01/02/2015,\"Smith, Jane \"\"JJ\"\"\",555-0100,,F\n"
        let result = CSVParser.parse(csv)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.athletes.first?.guardianName, "Smith, Jane \"JJ\"")
        XCTAssertEqual(result.athletes.first?.guardianPhone, "555-0100")
    }

    func testCRLFLineEndingsAndBlankLinesAreTolerated() {
        let csv = "FirstName,LastName,DateOfBirth\r\nAva,Smith,01/02/2015\r\n\r\nLiam,Brown,03/14/2016\r\n"
        let result = CSVParser.parse(csv)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.athletes.map(\.fullName), ["Ava Smith", "Liam Brown"])
    }

    func testHeaderOnlyFileIsAnError() {
        let result = CSVParser.parse(header)
        XCTAssertTrue(result.athletes.isEmpty)
        XCTAssertEqual(result.errors, ["File is empty or has only a header row."])
    }

    func testInvalidRowsAreSkippedWithNumberedErrors() {
        let csv = header
            + "Ava,Smith\n"                 // row 2: too few columns
            + " ,Smith,01/02/2015\n"        // row 3: blank first name
            + "Ava, ,01/02/2015\n"          // row 4: blank last name
            + "Ava,Smith,2015-01-02\n"      // row 5: wrong date format
            + "Ava,Smith,01/02/2999\n"      // row 6: future date
            + "Liam,Brown,03/14/2016\n"     // row 7: valid
        let result = CSVParser.parse(csv)
        XCTAssertEqual(result.athletes.map(\.fullName), ["Liam Brown"])
        XCTAssertEqual(result.errors.count, 5)
        for (offset, error) in result.errors.enumerated() {
            XCTAssertTrue(error.hasPrefix("Row \(offset + 2):"), error)
        }
        XCTAssertTrue(result.errors[1].contains("First name"), result.errors[1])
        XCTAssertTrue(result.errors[2].contains("Last name"), result.errors[2])
        XCTAssertTrue(result.errors[4].contains("future"), result.errors[4])
    }

    func testRowNumbersCountBlankLines() {
        // Error rows match the spreadsheet: blank lines are skipped but still counted.
        let result = CSVParser.parse(header + "\nAva,Smith\n")
        XCTAssertEqual(result.errors.first?.hasPrefix("Row 3:"), true, result.errors.first ?? "")
    }

    func testRowNumbersCountAQuotedMultiLineRecordAsOneRow() {
        let csv = header + "Ava,Smith,01/02/2015,\"Jane\nSmith\"\nLiam,Brown\n"
        let result = CSVParser.parse(csv)
        XCTAssertEqual(result.errors.first?.hasPrefix("Row 3:"), true, result.errors.first ?? "")
    }

    func testGenderParsingIsCaseInsensitiveAndOptional() {
        let csv = header
            + "A,One,01/02/2015,,,,Male\n"
            + "B,Two,01/02/2015,,,,girl\n"
            + "C,Three,01/02/2015,,,,M\n"
            + "D,Four,01/02/2015,,,,nonbinary\n"
            + "E,Five,01/02/2015\n"
        let genders = CSVParser.parse(csv).athletes.map(\.gender)
        XCTAssertEqual(genders, [.male, .female, .male, nil, nil])
    }

    // MARK: - Dates

    func testTwoDigitYearIsRejectedNotImportedAsYearZeroZeroXX() {
        let result = CSVParser.parse(header + "Liam,Brown,3/14/16\n")
        XCTAssertTrue(result.athletes.isEmpty)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].contains("4-digit year"), result.errors[0])
    }

    func testFourDigitYearImports() {
        let result = CSVParser.parse(header + "Liam,Brown,03/14/2016\n")
        XCTAssertEqual(result.athletes.count, 1)
        XCTAssertEqual(result.athletes.first.map { SeasonContext.year(of: $0.dateOfBirth) }, 2016)
    }

    // MARK: - Guardian email

    func testInvalidGuardianEmailIsDroppedButTheAthleteImports() {
        let result = CSVParser.parse(header + "Ava,Smith,01/02/2015,Jane,,jane smith@example.com,F\n")
        XCTAssertEqual(result.athletes.count, 1)
        XCTAssertNil(result.athletes.first?.guardianEmail)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].contains("imported without it"), result.errors[0])
    }

    func testValidGuardianEmailIsTrimmedAndKept() {
        let result = CSVParser.parse(header + "Ava,Smith,01/02/2015,Jane,, jane@example.com ,F\n")
        XCTAssertEqual(result.athletes.first?.guardianEmail, "jane@example.com")
        XCTAssertEqual(result.errors, [])
    }
}

/// Mirrors the backend's `@Email` closely enough that anything accepted here also syncs.
final class EmailValidationTests: XCTestCase {

    func testAcceptsOrdinaryAddresses() {
        for email in ["jane@example.com", "o'neil+club@mail.example.ca", "user@gmail", "a.b-c_d@x-y.org"] {
            XCTAssertTrue(email.isPlausibleEmail, email)
        }
    }

    func testRejectsAddressesTheBackendWouldRefuse() {
        for email in ["", "jane", "jane@", "@example.com", "a@b@c.com", "jane smith@example.com",
                      "jane@example..com", ".jane@example.com", "jane.@example.com", "jane@example.com.",
                      "jane@-example.com", "jane,smith@example.com"] {
            XCTAssertFalse(email.isPlausibleEmail, email)
        }
    }
}
