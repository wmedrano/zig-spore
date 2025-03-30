const std = @import("std");

pub const Error = error{
    BadArg,
    BadDefine,
    BadFunction,
    BadIf,
    BadWhen,
    ExpectedIdentifier,
    /// An object (that is garbage collected) was not found. This may
    /// happen if the object is referenced after it has been garbage
    /// collected.
    ObjectNotFound,
    StackFrameUnderflow,
    StackOverflow,
    ValueAlreadyDefined,
    WrongArity,
} ||
    ToZigError ||
    AstError ||
    std.mem.Allocator.Error;

pub const ToZigError = error{
    WrongType,
    ObjectNotFound,
};

pub const AstError = error{
    BadString,
    EmptyAtom,
    EmptyKey,
    EmptySymbol,
    TooManyQuotes,
    UnexpectedCloseParen,
    UnexpectedEmptyExpression,
} || std.mem.Allocator.Error;
