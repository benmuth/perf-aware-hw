const std = @import("std");
const print = std.debug.print;

const data = @import("generate_data.zig");
const HaversinePair = data.Pair;

// struct buffer
// {
//     size_t Count;
//     u8 *Data;
// };

pub const Buffer = struct {
    count: usize,
    data: [*]u8,

    fn isInBounds(self: Buffer, at: u64) bool {
        return at < self.count;
    }

    fn isEqual(this: Buffer, that: Buffer) bool {
        if (this.count != that.count) {
            return false;
        }
        for (0..this.count) |i| {
            if (this.data[i] != that.data[i]) {
                return false;
            }
        }
        return true;
    }

    pub fn init(allocator: std.mem.Allocator, count: usize) !Buffer {
        var result: Buffer = undefined;
        result.data = (try allocator.alloc(u8, count)).ptr;
        result.count = count;
        return result;
    }

    pub fn deinit(self: *Buffer, allocator: std.mem.Allocator) void {
        // if (self != null) {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            allocator.destroy(self.data[0..1]);
            self.data += i;
        }
    }
    // }
};

const TokenType = enum {
    end_of_stream,
    _error,

    open_brace,
    open_bracket,
    close_brace,
    close_bracket,
    comma,
    colon,
    semi_colon,
    string_literal,
    number,
    _true,
    _false,
    _null,

    count,
};

const JSON_Token = struct {
    type: TokenType,
    value: Buffer,
};

const JSON_Element = struct {
    label: Buffer,
    value: Buffer,
    first_sub_element: ?*JSON_Element,

    next_sibling: ?*JSON_Element,
};

const JSON_Parser = struct {
    source: Buffer,
    at: u64,
    had_error: bool,
};

fn isJSONDigit(source: Buffer, at: u64) bool {
    var result = false;
    if (source.isInBounds(at)) {
        const val = source.data[at];
        result = ((val >= '0') and (val <= '9'));
    }
    return result;
}

fn isJSONWhitespace(source: Buffer, at: u64) bool {
    var result = false;
    if (source.isInBounds(at)) {
        const val = source.data[at];
        result = ((val == ' ') or (val == '\t') or (val == '\n') or (val == '\r'));
    }
    return result;
}

fn isParsing(parser: *JSON_Parser) bool {
    const result = !parser.had_error and parser.source.isInBounds(parser.at);
    return result;
}

fn parserError(parser: *JSON_Parser, token: JSON_Token, message: []const u8) void {
    parser.had_error = true;
    print("ERROR: \"{s}\" - {s}\n", .{ token.value.data[0..token.value.count], message });
}

fn parseKeyword(source: Buffer, at: *u64, keyword_remaining: Buffer, type_: TokenType, result: *JSON_Token) void {
    if ((source.count - at.*) >= keyword_remaining.count) {
        var check = source;
        check.data += at.*;
        check.count = keyword_remaining.count;
        if (check.isEqual(keyword_remaining)) {
            result.type = type_;
            result.value.count += keyword_remaining.count;
            at.* += keyword_remaining.count;
        }
    }
}

fn getJSONToken(parser: *JSON_Parser) JSON_Token {
    var result: JSON_Token = undefined;

    const source = parser.source;
    var at = parser.at;

    while (isJSONWhitespace(source, at)) {
        at += 1;
    }

    if (source.isInBounds(at)) {
        result.type = TokenType._error;
        result.value.count = 1;
        result.value.data = source.data + at;
        var val = source.data[at];
        at += 1;
        switch (val) {
            '{' => result.type = TokenType.open_brace,
            '[' => result.type = TokenType.open_bracket,
            '}' => result.type = TokenType.close_brace,
            ']' => result.type = TokenType.close_bracket,
            ',' => result.type = TokenType.comma,
            ':' => result.type = TokenType.colon,
            ';' => result.type = TokenType.semi_colon,
            'f' => {
                const keyword_remaining: []const u8 = "alse";
                const buf = Buffer{ .count = keyword_remaining.len, .data = @constCast(keyword_remaining.ptr) };
                parseKeyword(source, &at, buf, TokenType._false, &result);
            },
            'n' => {
                const keyword_remaining: []const u8 = "ull";
                const buf = Buffer{ .count = keyword_remaining.len, .data = @constCast(keyword_remaining.ptr) };
                parseKeyword(source, &at, buf, TokenType._null, &result);
            },
            't' => {
                const keyword_remaining: []const u8 = "rue";
                const buf = Buffer{ .count = keyword_remaining.len, .data = @constCast(keyword_remaining.ptr) };
                parseKeyword(source, &at, buf, TokenType._true, &result);
            },
            '"' => {
                result.type = TokenType.string_literal;
                const string_start = at;
                while (source.isInBounds(at) and source.data[at] != '"') {
                    if ((source.isInBounds(at + 1)) and (source.data[at] == '\\') and (source.data[at + 1] == '"')) {
                        at += 1;
                    }
                    at += 1;
                }
                result.value.data = source.data + string_start;
                result.value.count = at - string_start;
                if (source.isInBounds(at)) {
                    at += 1;
                }
            },
            '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                const start: u64 = at - 1;
                result.type = TokenType.number;
                if ((val == '-') and (source.isInBounds(at))) {
                    val = source.data[at];
                    at += 1;
                }
                if (val != '0') {
                    while (isJSONDigit(source, at)) {
                        at += 1;
                    }
                }
                if (source.isInBounds(at) and source.data[at] == '.') {
                    at += 1;
                    while (isJSONDigit(source, at)) {
                        at += 1;
                    }
                }
                if (source.isInBounds(at) and (source.data[at] == 'e' or source.data[at] == 'E')) {
                    at += 1;
                    if (source.isInBounds(at) and (source.data[at] == '+' or source.data[at] == '-')) {
                        at += 1;
                    }
                    while (isJSONDigit(source, at)) {
                        at += 1;
                    }
                }
                result.value.count = at - start;
            },
            else => {},
        }
    }
    parser.at = at;
    return result;
}

fn parseJSONElement(allocator: std.mem.Allocator, parser: *JSON_Parser, label: Buffer, value: JSON_Token) ParseError!?*JSON_Element {
    var valid = true;

    var sub_element: ?*JSON_Element = null;
    if (value.type == TokenType.open_bracket) {
        sub_element = try parseJSONList(allocator, parser, TokenType.close_bracket, false);
    } else if (value.type == TokenType.open_brace) {
        sub_element = try parseJSONList(allocator, parser, TokenType.close_brace, true);
    } else if ((value.type == TokenType.string_literal) or (value.type == TokenType._true) or (value.type == TokenType._false) or (value.type == TokenType._null) or (value.type == TokenType.number)) {} else {
        valid = false;
    }

    var result: ?*JSON_Element = null;

    if (valid) {
        result = try allocator.create(JSON_Element);
        result.?.label = label;
        result.?.value = value.value;
        result.?.first_sub_element = sub_element;
        result.?.next_sibling = null;
    }
    return result;
}

fn parseJSONList(allocator: std.mem.Allocator, parser: *JSON_Parser, end_type: TokenType, has_labels: bool) ParseError!?*JSON_Element {
    var first_element: ?*JSON_Element = null;
    var last_element: ?*JSON_Element = null;

    while (isParsing(parser)) {
        var label: Buffer = undefined;
        var value = getJSONToken(parser);
        if (has_labels) {
            if (value.type == TokenType.string_literal) {
                label = value.value;

                const colon = getJSONToken(parser);
                if (colon.type == TokenType.colon) {
                    value = getJSONToken(parser);
                } else {
                    parserError(parser, colon, "Expected colon after field name");
                }
            } else if (value.type != end_type) {
                parserError(parser, value, "Unexpected token in JSON");
            }
        }

        const element: ?*JSON_Element = try parseJSONElement(allocator, parser, label, value);
        if (element != null) {
            if (last_element != null) {
                last_element.?.next_sibling = element;
            } else {
                first_element = element;
            }
            last_element = element;
        } else if (value.type == end_type) {
            break;
        } else {
            parserError(parser, value, "Unexpected token in JSON");
        }

        const comma = getJSONToken(parser);
        if (comma.type == end_type) {
            break;
        } else if (comma.type != TokenType.comma) {
            parserError(parser, comma, "Unexpected token in JSON");
        }
    }
    return first_element;
}

fn parseJSON(allocator: std.mem.Allocator, input_json: Buffer) ParseError!?*JSON_Element {
    var parser: JSON_Parser = undefined;
    parser.source = input_json;
    const label = try Buffer.init(allocator, 0);
    const result: ?*JSON_Element = try parseJSONElement(allocator, &parser, label, getJSONToken(&parser));
    return result;
}

fn freeJSON(allocator: std.mem.Allocator, element: ?*JSON_Element) void {
    var current_element = element;
    while (current_element) |elem| {
        const free_element: *JSON_Element = elem;
        current_element = elem.next_sibling;
        freeJSON(allocator, free_element.first_sub_element);
        allocator.destroy(free_element);
    }
}

fn lookupElement(object: ?*JSON_Element, element_name: Buffer) ?*JSON_Element {
    var result: ?*JSON_Element = null;

    if (object != null) {
        var search: ?*JSON_Element = object.?.first_sub_element;
        while (search) |elem| {
            if (elem.label.isEqual(element_name)) {
                result = elem;
                break;
            }
            search = elem.next_sibling;
        }
    }

    return result;
}

fn convertJSONSign(source: Buffer, at_result: *u64) f64 {
    var at = at_result.*;
    var result: f64 = 1.0;
    if (source.isInBounds(at) and (source.data[at] == '-')) {
        result = -1.0;
        at += 1;
    }

    at_result.* = at;
    return result;
}

fn convertJSONNumber(source: Buffer, at_result: *u64) f64 {
    var at: u64 = at_result.*;

    var result: f64 = 0.0;

    while (source.isInBounds(at)) {
        const char: u8 = source.data[at] - '0';
        if (char < 10) {
            // const charf: f64 = @floatFromInt(char)
            result = 10.0 * result + @as(f64, @floatFromInt(char));
            at += 1;
        } else {
            break;
        }
    }

    at_result.* = at;
    return result;
}

fn convertElementToF64(object: *JSON_Element, element_name: Buffer) f64 {
    var result: f64 = 0.0;

    const element: ?*JSON_Element = lookupElement(object, element_name);

    if (element != null) {
        const source: Buffer = element.?.value;
        var at: u64 = 0;
        const sign: f64 = convertJSONSign(source, &at);
        var number: f64 = convertJSONNumber(source, &at);

        if (source.isInBounds(at) and (source.data[at] == '.')) {
            at += 1;
            var c: f64 = 1.0 / 10.0;
            while (source.isInBounds(at)) {
                const char: u8 = source.data[at] - '0';
                if (char < 10) {
                    number = number + c * @as(f64, @floatFromInt(char));
                    c *= 1.0 / 10.0;
                    at += 1;
                } else {
                    break;
                }
            }
        }
        if (source.isInBounds(at) and ((source.data[at] == 'e') or (source.data[at] == 'E'))) {
            at += 1;
            if (source.isInBounds(at) and source.data[at] == '+') {
                at += 1;
            }

            const exponent_sign: f64 = convertJSONSign(source, &at);
            const exponent: f64 = exponent_sign * convertJSONNumber(source, &at);
            number *= std.math.pow(f64, 10.0, exponent);
        }
        result = sign * number;
    }

    return result;
}

pub fn parseHaversinePairs(allocator: std.mem.Allocator, input_json: Buffer, max_pair_count: u64, pairs: []HaversinePair) !u64 {
    const pair_ptr = pairs.ptr;
    var pair_count: u64 = 0;

    const json: ?*JSON_Element = try parseJSON(allocator, input_json);
    const array_label: []const u8 = "pairs";
    const array_label_buffer = Buffer{ .count = array_label.len, .data = @constCast(array_label.ptr) };
    const pairs_array: ?*JSON_Element = lookupElement(json, array_label_buffer);

    const x0_label: []const u8 = "x0";
    const y0_label: []const u8 = "y0";
    const x1_label: []const u8 = "x1";
    const y1_label: []const u8 = "y1";

    const x0_buffer = Buffer{ .count = x0_label.len, .data = @constCast(x0_label.ptr) };
    const y0_buffer = Buffer{ .count = y0_label.len, .data = @constCast(y0_label.ptr) };
    const x1_buffer = Buffer{ .count = x1_label.len, .data = @constCast(x1_label.ptr) };
    const y1_buffer = Buffer{ .count = y1_label.len, .data = @constCast(y1_label.ptr) };

    if (pairs_array != null) {
        var element: ?*JSON_Element = pairs_array.?.first_sub_element;
        while (element != null and (pair_count < max_pair_count)) {
            var pair: [*]HaversinePair = pair_ptr + pair_count;
            pair_count += 1;

            pair[0].x0 = convertElementToF64(element.?, x0_buffer);
            pair[0].y0 = convertElementToF64(element.?, y0_buffer);
            pair[0].x1 = convertElementToF64(element.?, x1_buffer);
            pair[0].y1 = convertElementToF64(element.?, y1_buffer);

            element = element.?.next_sibling;
        }
    }

    print("pairs sample: {any}\n", .{pairs[0..1]});
    freeJSON(allocator, json);
    return pair_count;
}

const ParseError = error{
    FailedToParse,
    OutOfMemory,
};
