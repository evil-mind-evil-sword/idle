//! idle - Trace construction and session management for Claude Code
//!
//! This library provides tools for building and querying traces from
//! Claude Code sessions, using tissue (issues) and zawinski (messages)
//! as data sources.

pub const trace = @import("trace.zig");
pub const hooks = @import("hooks.zig");

/// Re-export trace types for convenience
pub const Trace = trace.Trace;
pub const TraceEvent = trace.TraceEvent;
pub const EventType = trace.EventType;

/// Re-export hook runner
pub const runHook = hooks.runHook;
