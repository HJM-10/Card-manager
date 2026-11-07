# Saved categories and history filters

Delivered 7 November 2026. Open **Home → Account purchases**.

Users can choose a category when recording a purchase, create custom categories, or change/clear the category from purchase details. Each account owns its categories and starts with Groceries, Food, Transport, Shopping, Bills and Other. Existing purchases remain uncategorized until assigned. Category changes also work for purchases on archived cards.

Merchant search and combined card/category/date filters run on the server before pagination. Archived cards remain selectable, and Uncategorized is an explicit option. Date ranges include both selected local calendar days; the API receives an inclusive start and exclusive next-day boundary in UTC. Clearing search and filters reloads the complete account history. Loading and retry do not show records from a previous filter.

Migration `003_categories_history.sql` preserves purchases and adds nullable category references with composite ownership foreign keys and a database trigger. Original creation categories are stored separately so a delayed creation retry cannot undo later recategorization. Category creation and selection do not change purchase amounts, dates, cards, audit-row counts or outbox-row counts.

## Verification

- `flutter test --no-pub`: 41 passed; the opt-in live test is skipped in the offline suite.
- `flutter analyze --no-pub`: no issues.
- Backend PostgreSQL integration suite: 14 passed. Coverage includes category ownership/validation, creation replay after recategorization, archived-card categorization, literal substring search, combined filters/pagination, local-midnight boundaries, invalid ranges and direct SQL attempts to assign another user's category.
- An upgrade test applies the category migration to a populated pre-category schema and verifies existing purchase amounts, identifiers, audit records and six starter categories.
- The live Flutter HTTP integration test passed against an isolated temporary PostgreSQL schema, including saved categories, custom-category duplicate rejection, combined filters and cross-user access denial. The schema was removed afterward.
- `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:8000`: successful.

The local development database was backed up before migration; existing purchase values were verified unchanged afterward. The six existing sample purchases in `test@test.com` were assigned their matching categories through the API. Local wallet statistics are separate; server reports and budgets remain future work. Status filters follow the declined-purchase/refund workflow. The backend retains its existing AnyIO deprecation warning.
