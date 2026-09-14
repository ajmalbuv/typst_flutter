use crate::api::typst::{TypstCompileError, TypstDiagnostic, TypstSeverity, TypstSourceLocation};
use crate::world::SimpleWorld;
use typst::World;
use typst::syntax::{DiagSpan, DiagSpanKind};

/// Resolves a [DiagSpan] against [world] to a 1-based (line, column) pair.
///
/// Returns None if the span is detached (no file id) or the source cannot
/// be retrieved — this is expected for diagnostics generated from built-in
/// Typst library code.
pub(crate) fn resolve_span(
    diag_span: DiagSpan,
    world: &SimpleWorld,
) -> Option<(TypstSourceLocation, TypstSourceLocation)> {
    let (id, range) = match diag_span.get() {
        DiagSpanKind::Number { id, num, sub_range } => {
            (id, world.source(id).ok()?.range(num, sub_range)?)
        }
        DiagSpanKind::Range { id, range } => (id, range),
        DiagSpanKind::Detached => return None,
    };

    let source = world.source(id).ok()?;
    let lines = source.lines();

    let (start_line, start_col) = lines.byte_to_line_column(range.start)?;
    let end_byte = range.end.saturating_sub(1);
    let (end_line, end_col) = lines
        .byte_to_line_column(end_byte)
        .unwrap_or((start_line, start_col));

    Some((
        TypstSourceLocation {
            line: (start_line + 1) as u32,
            column: (start_col + 1) as u32,
        },
        TypstSourceLocation {
            line: (end_line + 1) as u32,
            column: (end_col + 1) as u32,
        },
    ))
}

/// Maps a single Typst [SourceDiagnostic] into our FRB-bridged [TypstDiagnostic].
///
/// Used for both compile errors and compile warnings.
pub(crate) fn map_diagnostic(
    e: &typst::diag::SourceDiagnostic,
    world: &SimpleWorld,
) -> TypstDiagnostic {
    let severity = match e.severity {
        typst::diag::Severity::Error => TypstSeverity::Error,
        typst::diag::Severity::Warning => TypstSeverity::Warning,
    };
    let (span_start, span_end) = resolve_span(e.span, world)
        .map(|(s, e)| (Some(s), Some(e)))
        .unwrap_or((None, None));
    TypstDiagnostic {
        severity,
        message: e.message.to_string(),
        hints: e.hints.iter().map(|h| h.v.to_string()).collect(),
        span_start,
        span_end,
    }
}

pub(crate) fn map_errors(
    errs: &[typst::diag::SourceDiagnostic],
    world: &SimpleWorld,
) -> TypstCompileError {
    TypstCompileError {
        diagnostics: errs.iter().map(|e| map_diagnostic(e, world)).collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use typst::diag::SourceDiagnostic;
    use typst::syntax::{DiagSpan, FileId, RootedPath, Span, VirtualPath, VirtualRoot};

    #[test]
    fn test_diag_span_range() {
        let world = SimpleWorld::new();
        let id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new("main.typ").unwrap(),
        ));
        let diag_span = DiagSpan::from_range(id, 0..1);
        let res = resolve_span(diag_span, &world);
        assert!(res.is_some());

        // Span on non-existent file
        let missing_id = FileId::new(RootedPath::new(
            VirtualRoot::Project,
            VirtualPath::new("non_existent.typ").unwrap(),
        ));
        let missing_diag_span = DiagSpan::from_range(missing_id, 0..1);
        assert!(resolve_span(missing_diag_span, &world).is_none());
    }

    #[test]
    fn test_diag_mapping_and_detached_span() {
        let world = SimpleWorld::new();

        // 1. Detached error
        let diag = SourceDiagnostic::error(Span::detached(), "Detached error");
        let mapped = map_diagnostic(&diag, &world);
        assert_eq!(mapped.severity, TypstSeverity::Error);
        assert_eq!(mapped.message, "Detached error");
        assert!(mapped.span_start.is_none());
        assert!(mapped.span_end.is_none());

        // 2. Warning diagnostic
        let warn_diag = SourceDiagnostic::warning(Span::detached(), "Detached warning");
        let mapped_warn = map_diagnostic(&warn_diag, &world);
        assert_eq!(mapped_warn.severity, TypstSeverity::Warning);

        // 3. map_errors helper
        let errs = vec![diag];
        let compile_err = map_errors(&errs, &world);
        assert_eq!(compile_err.diagnostics.len(), 1);
    }
}
