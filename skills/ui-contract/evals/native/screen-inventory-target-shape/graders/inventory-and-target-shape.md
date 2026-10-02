---
type: llm
weight: 1
---

The `ui-contract.md` beside the consultation must open with an inventory of the screens
the change reaches: the users list AND the secondary per-project access view
(`ProjectAccessView.vue`), plus the add-user form the list's "Añadir usuario" action
opens. Each inventoried screen has its own state matrix (no blank cell). The add form's
target shape (page, dialog or panel) is recorded as an open question or pending owner
decision, not stated as the dialog copied from today's `InviteUserDialog`.

Fails if: the access view has no state matrix of its own or appears only in passing; the
add form is recorded as a dialog because it is one today, with no open question about its
target form; the inventory is absent.

Does not count against it: reading the consultation folder, a harness-absent remark.
