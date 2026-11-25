# Feature map

How a user reaches each feature, and the command that proves it works. Run a row's command when a change touches that workflow, and before you say "done". When Steve tests a workflow by hand more than once, add a row and a check for it.

| Feature | User path | Check command | Expected result |
|---|---|---|---|
| <Feature name> | <Steps the user takes, with the exact labels and keys> | `<one command, for example a focused test>` | <What passes, and what the check proves> |

Limits: <what the check does not cover, for example the drawn UI or a decision made in private code>.

Example (File_manager pilot, 2026-11-25): "Copy a file to the other pane" - select a file in the left pane, press F5; check `cargo test -q -p fm-app --test feature_copy` runs the real file system inside a temporary test folder through the app's key and click calls.
