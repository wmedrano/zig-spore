const std = @import("std");

pub const Error = error{
    BadArg,
    BadDefine,
    BadFunction,
    BadIf,
    BadWhen,
    ExpectedIdentifier,
    ExpectedFunction,
    StackFrameUnderflow,
    StackOverflow,
    SymbolNotFound,
    ValueAlreadyDefined,
    WrongArity,
} ||
    ToZigError ||
    SexpError ||
    std.mem.Allocator.Error;

pub const ToZigError = error{
    WrongType,
    /// An object (that is garbage collected) was not found. This may
    /// happen if the object is referenced after it has been garbage
    /// collected.
    ObjectNotFound,
};

pub const SexpError = error{
    BadString,
    EmptyAtom,
    EmptyKey,
    EmptySymbol,
    TooManyQuotes,
    UnexpectedCloseParen,
    UnexpectedEmptyExpression,
} || std.mem.Allocator.Error;
