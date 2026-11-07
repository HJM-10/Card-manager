import csv
import hashlib
import io
from decimal import Decimal
from uuid import UUID, uuid4

from fastapi import HTTPException
from psycopg.types.json import Jsonb
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .purchases import PurchaseInput, TRANSACTION_SELECT, matching_purchase, save_purchase

MAX_BYTES = 256 * 1024
MAX_ROWS = 500
REQUIRED = {'reference', 'merchant', 'amount', 'occurred_at', 'channel'}
DUMMY_REFERENCE = UUID('00000000-0000-4000-8000-000000000000')


class CsvPreviewInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    card_id: UUID
    file_name: str = Field(min_length=1, max_length=120)
    csv_text: str = Field(min_length=1, max_length=MAX_BYTES)


class CsvConfirmation(BaseModel):
    model_config = ConfigDict(extra='forbid')
    preview_token: UUID


def parse_csv(text):
    try:
        byte_length = len(text.encode('utf-8'))
    except UnicodeError:
        raise HTTPException(422, 'CSV text must be valid UTF-8') from None
    if byte_length > MAX_BYTES:
        raise HTTPException(413, 'Choose a CSV file no larger than 256 KiB')
    if '\x00' in text:
        raise HTTPException(422, 'CSV text contains unsupported null characters')
    reader = csv.reader(io.StringIO(text.lstrip('\ufeff'), newline=''), strict=True)
    try:
        headers = [h.strip().lower() for h in next(reader)]
        if len(headers) != len(set(headers)) or not REQUIRED.issubset(headers) or set(headers) - REQUIRED - {'category'}:
            raise HTTPException(422, 'CSV columns must be reference, merchant, amount, occurred_at, channel, with optional category')
        rows = []
        for values in reader:
            if not values or all(not value.strip() for value in values):
                continue
            if len(rows) >= MAX_ROWS:
                raise HTTPException(422, 'A CSV file can contain at most 500 purchases')
            rows.append({'row': len(rows) + 2, 'values': dict(zip(headers, [v.strip() for v in values])), 'bad_columns': len(values) != len(headers)})
        if not rows:
            raise HTTPException(422, 'The CSV file has no purchase rows')
        return rows
    except (StopIteration, csv.Error, UnicodeError):
        raise HTTPException(422, 'The CSV file is empty or malformed. Use UTF-8 comma-separated values with valid quoting.') from None


def body_for_row(row, card_id):
    return PurchaseInput(card_id=card_id, merchant=row['merchant'], amount=row['amount'],
                         occurred_at=row['occurred_at'], channel=row['channel'],
                         category_id=row.get('category_id'), source_reference=DUMMY_REFERENCE)


def classify_rows(db, user_id, card_id, parsed):
    # Ask PostgreSQL to apply the same case folding as its category index.
    names = {row['key']: row for row in db.execute('SELECT id, name, lower(name) AS key FROM categories WHERE user_id = %s', (user_id,)).fetchall()}
    category_names = [entry['values'].get('category', '') for entry in parsed]
    folded_names = {r['original']: r['folded'] for r in db.execute('SELECT name AS original, lower(name) AS folded FROM unnest(%s::text[]) AS incoming(name)', (category_names,)).fetchall()}
    references = [entry['values'].get('reference', '') for entry in parsed]
    existing = {r['source_reference']: r for r in db.execute(TRANSACTION_SELECT + " WHERE t.user_id = %s AND t.card_id = %s AND t.source = 'csv' AND t.source_reference = ANY(%s)", (user_id, card_id, references)).fetchall()}
    seen = {}
    results = []
    for entry in parsed:
        raw = entry['values']
        row = {'row': entry['row'], **{key: raw.get(key, '')[:200] for key in REQUIRED},
               'category': raw.get('category', '')[:50], 'category_id': None, 'state': 'ready', 'message': 'Ready to import'}
        errors = []
        if entry['bad_columns']:
            errors.append('The number of values does not match the columns')
        if not 1 <= len(raw.get('reference', '')) <= 100:
            errors.append('Reference must contain 1–100 characters')
        category_name = raw.get('category', '')
        if category_name:
            folded = folded_names[category_name]
            category = names.get(folded)
            if category is None:
                errors.append('Category not found. Create it in your account first')
            else:
                row['category_id'] = str(category['id'])
                row['category'] = category['name']
        try:
            body = body_for_row(row, card_id)
        except ValidationError as error:
            messages = {'merchant': 'Merchant must contain 1–100 characters',
                        'amount': 'Amount must be positive PKR with exactly two decimal places',
                        'occurred_at': 'Date must include a timezone and be in UTC years 2000–2100',
                        'channel': 'Channel must be online or pos'}
            errors.extend(dict.fromkeys(messages.get(e['loc'][0], 'Invalid purchase value') for e in error.errors()))
            body = None
        if errors:
            row.update(state='error', message='; '.join(errors))
        else:
            row['amount'] = format(Decimal(body.amount), '.2f')
            row['occurred_at'] = body.occurred_at.isoformat()
            signature = (body.merchant, Decimal(body.amount), body.occurred_at, body.channel, body.category_id)
            previous = seen.get(row['reference'])
            stored = existing.get(row['reference'])
            if previous is not None and previous != signature:
                row.update(state='error', message='This file repeats the reference with different purchase details')
            elif stored is not None and not matching_purchase(stored, body):
                row.update(state='error', message='This reference already exists with different purchase details')
            elif previous is not None or stored is not None:
                row.update(state='duplicate', message='Matching reference; will be skipped')
            seen.setdefault(row['reference'], signature)
        results.append(row)
    return results


def public_batch(batch):
    rows = batch['rows']
    confirmed = batch['status'] == 'confirmed'
    return {'id': batch['id'], 'file_name': batch['file_name'], 'status': batch['status'],
            'preview_token': batch['preview_token'], 'rows': rows,
            'ready_count': sum(r['state'] == 'ready' for r in rows),
            'duplicate_count': batch['duplicate_count'] if confirmed else sum(r['state'] == 'duplicate' for r in rows),
            'error_count': sum(r['state'] == 'error' for r in rows),
            'imported_count': batch['imported_count'],
            'total_amount': format(batch['total_amount'] if confirmed else sum((Decimal(r['amount']) for r in rows if r['state'] == 'ready'), Decimal('0')), '.2f'),
            'can_confirm': not confirmed and not any(r['state'] == 'error' for r in rows)}


def preview_import(db, user_id, body):
    filename = body.file_name.strip()
    if not filename.lower().endswith('.csv') or '/' in filename or '\\' in filename or any(ord(c) < 32 for c in filename):
        raise HTTPException(422, 'Choose a .csv file with a simple file name')
    parsed = parse_csv(body.csv_text)
    card = db.execute('SELECT archived FROM card_profiles WHERE user_id = %s AND id = %s', (user_id, body.card_id)).fetchone()
    if card is None or card['archived']:
        raise HTTPException(404, 'Active card not found')
    file_hash = hashlib.sha256(body.csv_text.lstrip('\ufeff').replace('\r\n', '\n').encode('utf-8')).hexdigest()
    db.execute('''INSERT INTO import_batches (id, user_id, card_id, file_name, file_hash, preview_token, rows)
        VALUES (%s, %s, %s, %s, %s, %s, '[]') ON CONFLICT (user_id, card_id, file_hash) DO NOTHING''',
        (uuid4(), user_id, body.card_id, filename, file_hash, uuid4()))
    batch = db.execute('SELECT * FROM import_batches WHERE user_id = %s AND card_id = %s AND file_hash = %s FOR UPDATE', (user_id, body.card_id, file_hash)).fetchone()
    if batch['status'] == 'confirmed':
        return public_batch(batch)
    rows = classify_rows(db, user_id, body.card_id, parsed)
    batch = db.execute('UPDATE import_batches SET rows = %s, preview_token = %s, file_name = %s WHERE id = %s RETURNING *', (Jsonb(rows), uuid4(), filename, batch['id'])).fetchone()
    return public_batch(batch)


def confirm_import(db, user_id, batch_id, token):
    owner = db.execute('SELECT card_id FROM import_batches WHERE user_id = %s AND id = %s', (user_id, batch_id)).fetchone()
    if owner is None:
        raise HTTPException(404, 'Import not found')
    # All import batches and manual writes on one card use the same lock order.
    card = db.execute('SELECT archived FROM card_profiles WHERE user_id = %s AND id = %s FOR NO KEY UPDATE', (user_id, owner['card_id'])).fetchone()
    batch = db.execute('SELECT * FROM import_batches WHERE user_id = %s AND id = %s FOR UPDATE', (user_id, batch_id)).fetchone()
    if batch['status'] == 'confirmed':
        return public_batch(batch)
    if card is None or card['archived']:
        raise HTTPException(404, 'Active card not found. Choose another card and preview again.')
    if batch['preview_token'] != token:
        raise HTTPException(409, 'This preview has changed. Preview the file again.')
    if any(r['state'] == 'error' for r in batch['rows']):
        raise HTTPException(422, 'Fix the CSV row errors and preview again before importing')
    imported = skipped = 0
    total = Decimal('0')
    rows = batch['rows']
    for row in rows:
        saved, created = save_purchase(db, user_id, body_for_row(row, batch['card_id']), source='csv', reference=row['reference'], import_batch_id=batch_id)
        if created and row['state'] == 'duplicate':
            raise HTTPException(409, 'History changed since this preview. Preview the file again.')
        imported += int(created)
        skipped += int(not created)
        if created:
            total += saved['amount']
        row['transaction_id'] = str(saved['id'])
        row['state'] = 'imported' if created else 'duplicate'
        row['message'] = 'Imported' if created else 'Matching reference; skipped'
    confirmed = db.execute("UPDATE import_batches SET status = 'confirmed', rows = %s, imported_count = %s, duplicate_count = %s, total_amount = %s, confirmed_at = now() WHERE id = %s RETURNING *", (Jsonb(rows), imported, skipped, total, batch_id)).fetchone()
    return public_batch(confirmed)
