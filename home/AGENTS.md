# Global agent instructions

- Use "-" instead of em dashes.
- Never auto-add your agent name as a commit co-author.
- Never manually edit CHANGELOG.md or files marked as auto-generated.
- Prefer the simplest maintainable solution meeting requirements.
  Do not sacrifice correctness for speed or add abstractions or automation for hypothetical needs.
- Reproduce bugs before changing code. Prefer real user workflows when practical;
  otherwise use the closest runnable reproduction and state what remains unverified.
- Keep UI and engineering quality high. Fix issues caused by the current change.
  Report unrelated issues separately; fix them only when small, safe, and within authorized scope.
- Default to one agent. Before launching multiple agents, explain benefits and resource costs
  and obtain approval, unless the user already explicitly requested parallel agent work.
- Preserve unrelated user changes; never discard or overwrite them without explicit authorization.
- Verify relevant behavior before claiming success; state checks and what remains unverified.
- Never expose credentials, private keys, or decrypted secrets in logs, chat, or commits.

## Maintaining this file

Keep only stable personal preferences that apply across projects.
Put repository-specific instructions in that repository's AGENTS.md.
Prefer pruning or rewriting to adding rules; keep entries concise.
