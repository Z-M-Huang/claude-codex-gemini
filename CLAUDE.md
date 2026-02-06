# Claude Code - Pipeline Agent

This is a multi-AI development pipeline orchestrated by Gemini.

## Project Context
- Runtime: Bun (TypeScript execution without compilation)
- Cross-platform: Windows, macOS, Linux
- All file paths use path.join() - never string concatenation with /

## Your Role
You are invoked by the Gemini orchestrator for specific tasks. Your instructions come from agent files in the agents/ directory. Follow those instructions precisely.

## Standards
Read and follow docs/standards.md for all coding and review work.

## Output Files
Write output to the file specified in your instructions. Use 2-space JSON indentation with trailing newline.
