## Context Usage

**Model:** claude-fable-5-1  
**Tokens:** 32.4k / 1m (3%)

### Estimated usage by category

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 4.8k | 0.5% |
| System tools | 2.6k | 0.3% |
| MCP tools (deferred) | 36.5k | 3.7% |
| System tools (deferred) | 13.3k | 1.3% |
| Memory files | 18.2k | 1.8% |
| Skills | 6.8k | 0.7% |
| Messages | 10 | 0.0% |
| Free space | 934.6k | 93.5% |
| Autocompact buffer | 33k | 3.3% |

### MCP Tools

| Tool | Server | Tokens |
|------|--------|--------|
| mcp__chrome-devtools__click | chrome-devtools | 244 |
| mcp__chrome-devtools__close_page | chrome-devtools | 147 |
| mcp__chrome-devtools__drag | chrome-devtools | 235 |
| mcp__chrome-devtools__emulate | chrome-devtools | 650 |
| mcp__chrome-devtools__evaluate_script | chrome-devtools | 536 |
| mcp__chrome-devtools__fill | chrome-devtools | 284 |
| mcp__chrome-devtools__fill_form | chrome-devtools | 435 |
| mcp__chrome-devtools__get_console_message | chrome-devtools | 198 |
| mcp__chrome-devtools__get_network_request | chrome-devtools | 361 |
| mcp__chrome-devtools__handle_dialog | chrome-devtools | 218 |
| mcp__chrome-devtools__hover | chrome-devtools | 208 |
| mcp__chrome-devtools__lighthouse_audit | chrome-devtools | 327 |
| mcp__chrome-devtools__list_console_messages | chrome-devtools | 567 |
| mcp__chrome-devtools__list_network_requests | chrome-devtools | 463 |
| mcp__chrome-devtools__list_pages | chrome-devtools | 88 |
| mcp__chrome-devtools__navigate_page | chrome-devtools | 435 |
| mcp__chrome-devtools__new_page | chrome-devtools | 341 |
| mcp__chrome-devtools__performance_analyze_insight | chrome-devtools | 301 |
| mcp__chrome-devtools__performance_start_trace | chrome-devtools | 417 |
| mcp__chrome-devtools__performance_stop_trace | chrome-devtools | 227 |
| mcp__chrome-devtools__press_key | chrome-devtools | 287 |
| mcp__chrome-devtools__resize_page | chrome-devtools | 184 |
| mcp__chrome-devtools__select_page | chrome-devtools | 184 |
| mcp__chrome-devtools__take_heapsnapshot | chrome-devtools | 207 |
| mcp__chrome-devtools__take_screenshot | chrome-devtools | 454 |
| mcp__chrome-devtools__take_snapshot | chrome-devtools | 352 |
| mcp__chrome-devtools__type_text | chrome-devtools | 202 |
| mcp__chrome-devtools__upload_file | chrome-devtools | 312 |
| mcp__chrome-devtools__wait_for | chrome-devtools | 241 |
| mcp__claude_ai_Google_Drive__copy_file | claude_ai_Google_Drive | 417 |
| mcp__claude_ai_Google_Drive__create_file | claude_ai_Google_Drive | 905 |
| mcp__claude_ai_Google_Drive__download_file_content | claude_ai_Google_Drive | 406 |
| mcp__claude_ai_Google_Drive__get_file_metadata | claude_ai_Google_Drive | 222 |
| mcp__claude_ai_Google_Drive__get_file_permissions | claude_ai_Google_Drive | 134 |
| mcp__claude_ai_Google_Drive__list_recent_files | claude_ai_Google_Drive | 403 |
| mcp__claude_ai_Google_Drive__read_file_content | claude_ai_Google_Drive | 878 |
| mcp__claude_ai_Google_Drive__search_files | claude_ai_Google_Drive | 851 |
| mcp__claude_ai_Google_Drive__share_file | claude_ai_Google_Drive | 315 |
| mcp__claude_ai_Google_Drive__trash_file | claude_ai_Google_Drive | 156 |
| mcp__claude_ai_Google_Drive__update_file | claude_ai_Google_Drive | 340 |
| mcp__claude_ai_Vercel__add_toolbar_reaction | claude_ai_Vercel | 335 |
| mcp__claude_ai_Vercel__buy_addon | claude_ai_Vercel | 693 |
| mcp__claude_ai_Vercel__buy_credits | claude_ai_Vercel | 863 |
| mcp__claude_ai_Vercel__buy_domain | claude_ai_Vercel | 1.3k |
| mcp__claude_ai_Vercel__buy_pro | claude_ai_Vercel | 570 |
| mcp__claude_ai_Vercel__change_toolbar_thread_resolve_status | claude_ai_Vercel | 341 |
| mcp__claude_ai_Vercel__check_domain_availability_and_price | claude_ai_Vercel | 187 |
| mcp__claude_ai_Vercel__create_git_project | claude_ai_Vercel | 902 |
| mcp__claude_ai_Vercel__deploy_to_vercel | claude_ai_Vercel | 834 |
| mcp__claude_ai_Vercel__edit_toolbar_message | claude_ai_Vercel | 335 |
| mcp__claude_ai_Vercel__get_access_to_vercel_url | claude_ai_Vercel | 364 |
| mcp__claude_ai_Vercel__get_agent_run | claude_ai_Vercel | 721 |
| mcp__claude_ai_Vercel__get_agent_run_trace | claude_ai_Vercel | 795 |
| mcp__claude_ai_Vercel__get_deployment | claude_ai_Vercel | 264 |
| mcp__claude_ai_Vercel__get_deployment_build_logs | claude_ai_Vercel | 716 |
| mcp__claude_ai_Vercel__get_domain_order | claude_ai_Vercel | 289 |
| mcp__claude_ai_Vercel__get_git_deployment_context | claude_ai_Vercel | 114 |
| mcp__claude_ai_Vercel__get_project | claude_ai_Vercel | 366 |
| mcp__claude_ai_Vercel__get_project_deployment_protection | claude_ai_Vercel | 417 |
| mcp__claude_ai_Vercel__get_purchase_quote | claude_ai_Vercel | 1k |
| mcp__claude_ai_Vercel__get_runtime_errors | claude_ai_Vercel | 570 |
| mcp__claude_ai_Vercel__get_runtime_logs | claude_ai_Vercel | 1.1k |
| mcp__claude_ai_Vercel__get_toolbar_thread | claude_ai_Vercel | 269 |
| mcp__claude_ai_Vercel__get_web_analytics | claude_ai_Vercel | 1.1k |
| mcp__claude_ai_Vercel__import-claude-design-from-url | claude_ai_Vercel | 276 |
| mcp__claude_ai_Vercel__list_agent_run_projects | claude_ai_Vercel | 568 |
| mcp__claude_ai_Vercel__list_agent_runs | claude_ai_Vercel | 846 |
| mcp__claude_ai_Vercel__list_deployments | claude_ai_Vercel | 225 |
| mcp__claude_ai_Vercel__list_projects | claude_ai_Vercel | 261 |
| mcp__claude_ai_Vercel__list_teams | claude_ai_Vercel | 103 |
| mcp__claude_ai_Vercel__list_toolbar_threads | claude_ai_Vercel | 494 |
| mcp__claude_ai_Vercel__pause_project | claude_ai_Vercel | 408 |
| mcp__claude_ai_Vercel__reply_to_toolbar_thread | claude_ai_Vercel | 299 |
| mcp__claude_ai_Vercel__search_vercel_documentation | claude_ai_Vercel | 494 |
| mcp__claude_ai_Vercel__unpause_project | claude_ai_Vercel | 398 |
| mcp__claude_ai_Vercel__update_project_deployment_protection | claude_ai_Vercel | 1.2k |
| mcp__claude_ai_Vercel__web_fetch_vercel_url | claude_ai_Vercel | 241 |
| mcp__context7__query-docs | context7 | 658 |
| mcp__context7__resolve-library-id | context7 | 1.1k |
| mcp__lighthouse__get_performance_score | lighthouse | 130 |
| mcp__lighthouse__run_audit | lighthouse | 230 |

### Memory Files

| Type | Path | Tokens |
|------|------|--------|
| User | /Users/yoelacevedo/.claude/CLAUDE.md | 2.4k |
| User | /Users/yoelacevedo/.claude/rules/database-protection.md | 1.4k |
| User | /Users/yoelacevedo/.claude/rules/e2e-testing.md | 818 |
| User | /Users/yoelacevedo/.claude/rules/artifacts-local-first.md | 1.5k |
| User | /Users/yoelacevedo/.claude/rules/aidex-conventions.md | 3k |
| User | /Users/yoelacevedo/.claude/rules/verification-before-claims.md | 748 |
| User | /Users/yoelacevedo/.claude/rules/memory-hygiene.md | 1.5k |
| User | /Users/yoelacevedo/.claude/rules/root-cause-first.md | 139 |
| User | /Users/yoelacevedo/.claude/rules/autonomy.md | 2.1k |
| User | /Users/yoelacevedo/.claude/rules/harness-lessons.md | 844 |
| Project | /Users/yoelacevedo/Documents/projects/aidex/CLAUDE.md | 2.5k |
| AutoMem | /Users/yoelacevedo/.claude/projects/-Users-yoelacevedo-Documents-projects-aidex/memory/MEMORY.md | 1.2k |

### Skills

| Skill | Source | Tokens |
|-------|--------|--------|
| aidex | User | ~260 |
| aidex-bugfix | User | ~210 |
| aidex-comm | User | ~290 |
| aidex-coverage | User | ~270 |
| aidex-decision | User | ~240 |
| aidex-plan | User | ~300 |
| aidex-plan-exec | User | ~190 |
| aidex-reference | User | ~240 |
| aidex-research | User | ~220 |
| aidex-review | User | ~300 |
| aidex-worktree | User | ~270 |
| dependency-updater | User | ~210 |
| git-commit | User | ~80 |
| session-handoff | User | ~420 |
| skill-trigger-eval | Project | < 20 |
| handoff | User | ~30 |
| restart | User | ~20 |
| ralph-loop:cancel-ralph | Plugin (ralph-loop) | < 20 |
| ralph-loop:help | Plugin (ralph-loop) | ~20 |
| ralph-loop:ralph-loop | Plugin (ralph-loop) | ~20 |
| skill-creator:skill-creator | Plugin (skill-creator) | ~120 |
| document-skills:xlsx | Plugin (document-skills) | ~320 |
| document-skills:docx | Plugin (document-skills) | ~290 |
| document-skills:pptx | Plugin (document-skills) | ~250 |
| document-skills:pdf | Plugin (document-skills) | ~150 |
| dataviz | Built-in | ~480 |
| update-config | Built-in | ~240 |
| keybindings-help | Built-in | ~80 |
| code-review | Built-in | ~270 |
| simplify | Built-in | ~60 |
| fewer-permission-prompts | Built-in | ~60 |
| loop | Built-in | ~120 |
| schedule | Built-in | ~130 |
| claude-api | Built-in | ~360 |
| workflow-authoring | Built-in | ~80 |
| run | Built-in | ~120 |
| init | Built-in | ~20 |
| security-review | Built-in | ~30 |

