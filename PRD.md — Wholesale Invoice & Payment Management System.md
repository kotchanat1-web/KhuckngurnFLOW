# PRD.md
# Wholesale Invoice & Payment Management System

## 1. Project Overview

เว็บแอปสำหรับบริษัทขายส่ง ใช้จัดการ **บิลขาย / Invoice / การรับชำระเงิน / หลักฐานการโอน / ยอดคงค้าง** โดยรับข้อมูลพื้นฐานจากโปรแกรม Express ผ่านไฟล์ `.SDF`

ระบบสามารถนำข้อมูลจาก SDF มาประมวลผลเป็น Invoice โดยมีเลขที่ IV สามารถค้นหาและเรียกดูย้อนหลังได้ พร้อมระบบบันทึกการรับเงินหลายรูปแบบ ได้แก่

1. เงินสด
2. เงินโอน + OCR Slip
3. เช็ค

ระบบสามารถ Match เงินที่รับเข้ากับ Invoice ที่ค้างชำระ และรองรับการชำระหลาย Invoice ในครั้งเดียว รวมถึงกรณีชำระบางส่วน / แบ่งจ่าย / ยอดไม่ตรงกับ Invoice

Backend ใช้ Supabase เพื่อให้หลาย Device ใช้งานพร้อมกันและข้อมูล Synchronize แบบ Real-time

---

# 2. Goals

## เป้าหมายหลัก

- ลดการลงข้อมูล Invoice ด้วยมือ
- Import ข้อมูลจาก Express SDF
- เก็บ Invoice และประวัติย้อนหลังทั้งหมด
- ติดตามยอดค้างชำระของลูกค้า
- บันทึกเงินสด / เงินโอน / เช็ค
- OCR Slip และเอกสาร PDF
- Auto Match ยอดรับเงินกับ Invoice
- รองรับการจ่ายหลายบิลในครั้งเดียว
- เก็บหลักฐานการชำระเงิน
- มี Dashboard สำหรับดูสถานะทางการเงิน
- รองรับหลาย Device
- ข้อมูล Real-time
- มี Audit Log ทุกการเปลี่ยนแปลง

---

# 3. Scope — MVP

## 3.1 Invoice Import

รองรับการนำเข้าข้อมูลจาก Express ในรูปแบบ

```text
.SDF
```

ระบบต้องสามารถอ่านข้อมูลสำคัญ เช่น

- Customer Code
- Customer Name
- Invoice Number
- Invoice Date
- Due Date
- Delivery Vehicle
- Sales Amount
- VAT
- Grand Total
- Paid Amount
- Outstanding Amount

### การสร้าง IV

เมื่อ Import สำเร็จ ระบบสร้าง Invoice Record โดยมี

```text
IV Number
Invoice Date
Customer
Delivery Vehicle
Total Amount
Paid Amount
Outstanding Amount
Status
```

สถานะ Invoice:

```text
UNPAID
PARTIAL
PAID
OVERPAID
CANCELLED
```

> Mapping ของ Field จาก SDF ควรออกแบบให้ Configurable เนื่องจากโครงสร้าง SDF ของ Express อาจแตกต่างกันตาม Version / Module

---

# 4. Invoice Management

## รายการ Invoice

สามารถค้นหาโดย

- IV Number
- Invoice Number
- Customer
- Customer Code
- วันที่
- รถส่งของ
- สถานะการชำระ

## Invoice Detail

แสดง

```text
IV Number
Invoice Date
Customer
Customer Code
Delivery Vehicle
Total
Paid
Outstanding
Payment History
Attachments
Audit History
```

สามารถเปิดดู Invoice เก่าได้โดยไม่จำกัดเฉพาะข้อมูลปัจจุบัน

---

# 5. Payment Management

ระบบรองรับ 3 ประเภท

## 5.1 Cash

User กรอก

```text
วันที่
จำนวนเงิน
ลูกค้า
หมายเหตุ
```

จำนวนเงินเป็น Numeric Input

---

## 5.2 Bank Transfer

รองรับ

- กรอกยอดเงินเอง
- Upload Slip
- OCR Slip
- อ่านข้อมูลจากรูปภาพ
- อ่าน PDF
- ตรวจสอบข้อมูลก่อนบันทึก

ข้อมูล OCR ที่ต้องการ:

```text
Transaction Date
Transaction Time
Amount
Sender Name
Receiver Name
Reference Number
Bank
```

User ต้องสามารถแก้ไขข้อมูล OCR ก่อนบันทึก

---

## 5.3 Cheque

ข้อมูล:

```text
Cheque Number
Bank
Cheque Date
Amount
Customer
Note
Attachment
```

สถานะ:

```text
PENDING
DEPOSITED
CLEARED
BOUNCED
CANCELLED
```

---

# 6. Payment Matching Engine

หัวใจของระบบคือการจับคู่เงินที่รับเข้ากับ Invoice

## Matching Priority

เมื่อมี Payment ใหม่ ระบบค้นหา Invoice ที่เกี่ยวข้องตามลำดับ

### Priority 1

ยอดเงินตรงกับ Invoice ที่ยังไม่ได้ชำระ

```text
Payment = Outstanding
```

---

### Priority 2

ยอดเงินตรงกับ Invoice ที่ชำระบางส่วน

```text
Payment = Remaining Balance
```

---

### Priority 3

Invoice ที่ยังไม่ชำระ และยอด Payment มากกว่า Invoice

ตัวอย่าง:

```text
Invoice = 10,000
Payment = 15,000
```

ระบบเสนอ:

```text
Invoice A = 10,000
Remaining = 5,000
```

และให้ User เลือกว่าจะ

```text
แบ่งจ่าย
ชำระหลายบิล
ยอดเกิน
เหตุผลอื่น
```

---

# 7. Partial Payment / Split Payment

รองรับกรณี

```text
Invoice = 100,000
Payment = 30,000
```

ระบบบันทึก

```text
Paid = 30,000
Outstanding = 70,000
Status = PARTIAL
```

และสามารถรับเงินเพิ่มเติมภายหลังได้

---

# 8. Multi-Invoice Payment

รองรับลูกค้าชำระหลาย Invoice พร้อมกัน

ตัวอย่าง

```text
IV001 = 10,000
IV002 = 20,000
IV003 = 15,000
IV004 = 30,000
IV005 = 25,000

Total = 100,000
```

ลูกค้าชำระ

```text
100,000
```

ระบบสามารถเลือก Invoice ทั้ง 5 ใบแล้ว Match Payment ครั้งเดียว

---

## Auto Allocation

ถ้า Payment ไม่เท่ากับยอดรวม Invoice

ระบบเสนอ Allocation

ตัวอย่าง:

```text
Payment = 70,000

IV001 10,000
IV002 20,000
IV003 40,000
IV004 30,000
```

ระบบสามารถเลือก

```text
IV001 + IV002 + IV003 = 70,000
```

หรือ User เลือกเอง

---

# 9. Payment Exception

หากยอดเงินไม่ตรงกับ Invoice ระบบต้องไม่บังคับ Match

ให้ User ระบุเหตุผล

ตัวเลือก:

```text
PARTIAL_PAYMENT
MULTIPLE_INVOICE
OVER_PAYMENT
ADVANCE_PAYMENT
DISCOUNT
BANK_FEE
OTHER
```

กรณี OTHER ต้องกรอกรายละเอียด

```text
Reason
Note
```

---

# 10. Payment Record

ทุก Payment ต้องมี

```text
Payment ID
Payment Date
Customer
Payment Type
Amount
Matched Amount
Unmatched Amount
Status
Created By
Created At
Updated At
```

---

# 11. Attachment Management

ระบบต้องสามารถเก็บไฟล์หลักฐาน เช่น

```text
Bank Slip
Cheque
Invoice
PDF
รูปภาพ
เอกสารอื่น ๆ
```

ไฟล์ต้องเชื่อมกับ Record ที่เกี่ยวข้อง

```text
Payment
Invoice
Customer
```

ใช้ Supabase Storage

ตัวอย่าง Path:

```text
/invoices/{invoice_id}/
/payments/{payment_id}/
/customers/{customer_id}/
```

---

# 12. Dashboard

## Daily Dashboard

แสดง

```text
ยอดขายวันนี้
ยอดรับเงินวันนี้
เงินสด
เงินโอน
เช็ค
จำนวน Invoice
Invoice ที่ชำระแล้ว
Invoice ที่ค้าง
ยอดค้างชำระ
```

---

## Outstanding Dashboard

แสดง

```text
ยอดค้างทั้งหมด
จำนวน Invoice ค้าง
ลูกค้าที่มียอดค้างสูงสุด
Invoice ที่ค้างนานที่สุด
ยอด Partial Payment
```

สามารถ Filter

```text
Today
This Week
This Month
Custom Date
Customer
Payment Status
```

---

# 13. Historical Data

สามารถเลือกวันที่เพื่อดูข้อมูลย้อนหลัง

```text
Date Picker
Start Date
End Date
```

ข้อมูลที่เรียกดูได้:

- Invoice
- Payment
- Slip
- Cheque
- Customer
- Matching History
- Audit Log

ข้อมูลย้อนหลังต้องไม่ถูกลบเมื่อมีการแก้ไข Record

---

# 14. Audit Log

ทุกการเปลี่ยนแปลงข้อมูลสำคัญต้องถูกบันทึก

ตัวอย่าง:

```text
User A
2026-08-26 14:32

แก้ไข Payment
จาก 10,000
เป็น 12,000
```

ข้อมูล:

```text
Audit ID
User
Action
Table
Record ID
Old Value
New Value
Timestamp
```

Action:

```text
CREATE
UPDATE
DELETE
IMPORT
MATCH
UNMATCH
UPLOAD
```

---

# 15. Multi-Device / Real-time

ระบบต้องรองรับ

```text
Computer 1
Computer 2
Tablet
Laptop
```

ใช้ Supabase Realtime

เมื่อ Device A เปลี่ยนข้อมูล:

```text
Payment = 10,000
```

Device B ต้องเห็นข้อมูลใหม่โดยไม่ต้อง Refresh

ตัวอย่าง Event:

```text
INSERT
UPDATE
DELETE
```

ควรใช้ Optimistic UI + Realtime Sync และมี Timestamp/version เพื่อป้องกันข้อมูลชนกัน

---

# 16. Supabase Architecture

## Supabase Services

ใช้

```text
Supabase Auth
Supabase PostgreSQL
Supabase Storage
Supabase Realtime
Row Level Security (RLS)
```

---

# 17. Suggested Database Schema

## customers

```text
id
customer_code
customer_name
address
phone
created_at
updated_at
```

## invoices

```text
id
iv_number
express_invoice_number
customer_id
invoice_date
due_date
delivery_vehicle
total_amount
paid_amount
outstanding_amount
status
source_file
created_at
updated_at
```

## payments

```text
id
payment_number
customer_id
payment_date
payment_type
amount
matched_amount
unmatched_amount
status
reference_number
note
created_by
created_at
updated_at
```

## payment_allocations

ใช้สำหรับ Payment 1 รายการจ่ายหลาย Invoice

```text
id
payment_id
invoice_id
allocated_amount
allocation_type
note
created_at
```

## attachments

```text
id
entity_type
entity_id
file_name
file_path
file_type
file_size
uploaded_by
created_at
```

## cheques

```text
id
payment_id
cheque_number
bank
cheque_date
status
created_at
updated_at
```

## audit_logs

```text
id
user_id
action
table_name
record_id
old_data
new_data
created_at
```

---

# 18. OCR Document System

ระบบมีหน้า

```text
Document OCR
```

รองรับ

```text
JPG
JPEG
PNG
WEBP
PDF
```

สามารถ

1. Upload
2. Preview
3. OCR
4. Extract Text
5. เลือกข้อความ
6. Copy
7. นำข้อความไปใช้กับ Form อื่น
8. Save Document
9. Link Document กับ Payment / Invoice

---

# 19. Gemini API Configuration

หน้า Settings มี

```text
Gemini API Key
```

และ

```text
[ ] Save API Key to Local Storage
```

ถ้า User เลือก Save:

```text
localStorage
```

ถ้าไม่เลือก:

```text
API Key อยู่เฉพาะ Session
```

### Security

สำหรับ Production ไม่ควรส่ง Gemini API Key จาก Browser โดยตรง

แนะนำ:

```text
Frontend
   ↓
Supabase Edge Function
   ↓
Gemini API
```

และเก็บ Secret ใน Supabase Environment / Secret Manager

Local Storage เหมาะสำหรับ MVP / Local Usage เท่านั้น

---

# 20. AI Model Selection

ให้แสดงเฉพาะ Model ที่กำหนด:

```text
gemini-3.6-flash
gemini-3.1-flash-lite
gemini-3.5-flash
gemini-3.5-flash-lite
gemma-4-26b-a4b-it
gemma-4-31b-it
```

Default:

```text
gemini-3.6-flash
```

มี Option:

```text
[✓] Try another model if fail
```

---

# 21. AI OCR Workflow

## Step 1 — Upload

User Upload:

```text
Image / PDF
```

---

## Step 2 — Validate

ตรวจสอบ:

```text
File Type
File Size
Image Resolution
PDF Page Count
```

---

## Step 3 — Preview

แสดง Document Preview

```text
Image Preview
หรือ
PDF Preview
```

---

## Step 4 — Send to AI

ส่ง Document ไปยัง Gemini พร้อม Prompt

สำหรับ Slip:

```text
อ่านข้อความจากเอกสารนี้

ต้องการข้อมูล:
- วันที่
- เวลา
- จำนวนเงิน
- ชื่อผู้โอน
- ชื่อผู้รับ
- ธนาคาร
- เลขอ้างอิงรายการ

ตอบกลับเป็น JSON เท่านั้น
ห้ามเดาข้อมูลที่อ่านไม่ได้
ถ้าไม่พบให้เป็น null
```

---

## Step 5 — Structured Output

ตัวอย่าง:

```json
{
  "transaction_date": null,
  "transaction_time": null,
  "amount": 15000,
  "sender_name": null,
  "receiver_name": null,
  "bank": null,
  "reference_number": null,
  "confidence": null
}
```

---

## Step 6 — Validate Result

Frontend ตรวจสอบ

```text
amount
date
reference_number
```

และแจ้งเตือนถ้า AI ส่งข้อมูลไม่ครบ

---

## Step 7 — User Review

ห้ามบันทึกข้อมูล OCR เข้า Database ทันที

ต้องแสดง:

```text
AI Result
↓
User Review
↓
Edit
↓
Confirm
↓
Save
```

---

## Step 8 — Auto Match

หลัง Confirm Payment

```text
Payment Matching Engine
```

ทำการค้นหา Invoice ที่เหมาะสม

---

## Step 9 — Fallback Model

ถ้า Model หลักเกิด Error:

```text
gemini-3.6-flash
        ↓ fail
gemini-3.1-flash-lite
        ↓ fail
gemini-3.5-flash
        ↓ fail
gemini-3.5-flash-lite
        ↓ fail
gemma-4-26b-a4b-it
        ↓ fail
gemma-4-31b-it
```

ควรมี Maximum Retry เพื่อป้องกันการยิง API ซ้ำโดยไม่จำเป็น

ตัวอย่าง:

```text
MAX_MODEL_RETRY = 2
```

หาก OCR ไม่สำเร็จ ให้ User กด

```text
Try Again
```

---

# 22. OCR Text Extraction Mode

นอกจาก Structured OCR ต้องมีโหมด

```text
Extract Text
```

สำหรับอ่านข้อความจากภาพ/PDF โดยตรง

UI:

```text
Document
──────────────
[ Preview ]

Extracted Text
──────────────
ข้อความที่ AI อ่านได้ทั้งหมด

[Copy]
[Copy Selected]
[Use Text]
```

User สามารถ Highlight ข้อความแล้วนำไปใช้ต่อได้

---

# 23. File Structure

สำหรับ MVP แนะนำโครงสร้าง:

```text
/
├── index.html
├── css/
│   └── style.css
├── js/
│   ├── app.js
│   ├── config.js
│   ├── supabase.js
│   ├── auth.js
│   ├── invoice.js
│   ├── payment.js
│   ├── matching.js
│   ├── ocr.js
│   ├── dashboard.js
│   ├── import-sdf.js
│   ├── storage.js
│   └── audit.js
├── assets/
│   ├── icons/
│   └── images/
└── README.md
```

---

# 24. HTML Structure

`index.html` ทำหน้าที่เป็น Application Shell

หลัก ๆ:

```text
<body>

  Sidebar

  Header

  Main Content
    ├── Dashboard
    ├── Invoice
    ├── Payments
    ├── OCR
    ├── Customers
    ├── Import SDF
    └── Settings

  Modal
    ├── Payment Modal
    ├── Invoice Detail
    ├── OCR Result
    └── Confirmation

</body>
```

ไม่ควรใส่ Business Logic จำนวนมากใน HTML

---

# 25. CSS Structure

`style.css`

แบ่งเป็น

```text
Variables
Reset
Layout
Sidebar
Header
Cards
Tables
Forms
Buttons
Modal
Upload Area
OCR Viewer
Dashboard
Responsive
Loading
Toast
```

Design เป้าหมาย:

```text
Desktop First
Responsive
Clean
Business Application
อ่านง่าย
ใช้สีเพื่อแสดงสถานะ
```

ตัวอย่าง Status:

```text
PAID
PARTIAL
UNPAID
OVERPAID
```

---

# 26. JavaScript Architecture

## app.js

ควบคุม

```text
Application Initialization
Routing
Global State
Event Binding
```

---

## supabase.js

จัดการ

```text
Supabase Client
Database
Realtime
Storage
```

---

## invoice.js

จัดการ

```text
Invoice CRUD
Search
Filter
Invoice Detail
```

---

## payment.js

จัดการ

```text
Cash
Transfer
Cheque
Payment CRUD
```

---

## matching.js

จัดการ

```text
Auto Match
Partial Payment
Multi Invoice
Over Payment
Unmatched Payment
```

---

## ocr.js

จัดการ

```text
Upload
Preview
Gemini Request
OCR Result
Fallback Model
Text Extraction
```

---

## import-sdf.js

จัดการ

```text
Upload SDF
Parse SDF
Field Mapping
Validation
Create Invoice
Import Summary
```

---

## dashboard.js

จัดการ

```text
Daily Summary
Outstanding
Payment Summary
Charts
```

---

# 27. SDF Import Workflow

```text
Upload SDF
     ↓
Validate File
     ↓
Parse SDF
     ↓
Map Express Fields
     ↓
Validate Data
     ↓
Preview
     ↓
User Confirm
     ↓
Create Customer
     ↓
Create Invoice
     ↓
Calculate Outstanding
     ↓
Save to Supabase
     ↓
Import Summary
```

Import Summary:

```text
Imported: 350
Created: 340
Updated: 8
Duplicate: 2
Error: 0
```

---

# 28. Duplicate Protection

ระบบต้องป้องกันการ Import Invoice ซ้ำ

ใช้ Unique Key เช่น

```text
company_id
+
express_invoice_number
```

หรือ Key ที่เหมาะสมตามโครงสร้างข้อมูลจริงของ Express

หากพบข้อมูลเดิม:

```text
SKIP
UPDATE
REPLACE
```

ควรให้ User เลือก Policy ก่อน Import

---

# 29. User Roles

MVP อย่างน้อย:

```text
ADMIN
USER
```

ADMIN สามารถ:

- Settings
- Import
- Edit/Delete
- ดู Audit Log
- จัดการ User

USER สามารถ:

- ดู Invoice
- ลง Payment
- OCR
- Match Payment
- ดู Dashboard

---

# 30. Realtime Data Flow

ตัวอย่าง Payment ใหม่:

```text
Device A
   ↓
Create Payment
   ↓
Supabase PostgreSQL
   ↓
Realtime Event
   ↓
Device B
   ↓
Update UI
```

ไม่ควรใช้วิธี Refresh หน้าเว็บเพื่อ Sync ข้อมูล

---

# 31. Error Handling

ทุก Operation ต้องมี

```text
Loading
Success
Error
Retry
```

ตัวอย่าง:

```text
OCR Failed
ไม่สามารถอ่านเอกสารได้

[Try Again]
[Change Model]
```

หรือ

```text
Import Failed

พบข้อมูลผิดพลาด 3 รายการ

[View Errors]
[Download Error Report]
```

---

# 32. Security

ต้องมี

```text
Supabase Auth
RLS
Role-based Access
Storage Access Control
Audit Log
```

ห้ามเก็บข้อมูลสำคัญใน Frontend แบบถาวรโดยไม่จำเป็น

Gemini API Key สำหรับ Production ควรใช้

```text
Supabase Edge Function
+
Supabase Secret
```

แทนการฝัง API Key ใน `index.html`

---

# 33. MVP Pages

ระบบ MVP ประกอบด้วย

```text
1. Login
2. Dashboard
3. Invoice
4. Invoice Detail
5. Payment
6. Payment Detail
7. Payment Matching
8. OCR Scanner
9. Customer
10. Import SDF
11. Historical Data
12. Settings
13. Audit Log
```

---

# 34. Dashboard MVP

หน้าแรกหลัง Login:

```text
┌───────────────────────────────────────┐
│ Today's Sales                         │
│ ฿ XXX,XXX                             │
├───────────────────────────────────────┤
│ Today's Payment                       │
│ ฿ XXX,XXX                             │
├───────────────┬───────────────────────┤
│ Cash          │ Transfer              │
│ ฿ XX,XXX      │ ฿ XX,XXX              │
├───────────────┴───────────────────────┤
│ Outstanding                           │
│ ฿ XXX,XXX                             │
└───────────────────────────────────────┘
```

---

# 35. Payment UX

หน้า Payment:

```text
[ + รับชำระเงิน ]

ประเภท
( ) เงินสด
( ) เงินโอน
( ) เช็ค

ลูกค้า
[ Search Customer ]

จำนวนเงิน
[              ]

วันที่
[              ]

หลักฐาน
[ Upload ]

[ OCR ]

        ↓

AI Result

จำนวนเงิน       15,000
วันที่           26/08/2026
Reference       XXXXX

[Confirm]
```

หลัง Confirm:

```text
Suggested Invoice

IV001   10,000
IV002   5,000

Total 15,000

[Match All]

[Confirm Payment]
```

---

# 36. Acceptance Criteria

## Invoice

- Import SDF ได้
- สร้าง IV ได้
- ค้นหา Invoice ได้
- เปิด Invoice ย้อนหลังได้
- คำนวณยอดคงค้างได้

## Payment

- ลงเงินสดได้
- ลงเงินโอนได้
- ลงเช็คได้
- Upload หลักฐานได้
- OCR Slip ได้
- Match Invoice ได้
- Partial Payment ได้
- Multi-Invoice Payment ได้
- Over Payment ได้

## OCR

- JPG/JPEG/PNG/WEBP ได้
- PDF ได้
- Extract Text ได้
- Structured Data ได้
- User แก้ไข OCR Result ได้
- Fallback Model ได้
- Copy Text ได้

## Realtime

- Device A เพิ่มข้อมูล
- Device B เห็นข้อมูลใหม่
- UPDATE Synchronize
- Audit Log ถูกสร้าง

---

# 37. Development Priority

## Phase 1 — Foundation

```text
HTML
CSS
JS Architecture
Supabase
Authentication
Database
RLS
```

## Phase 2 — Invoice

```text
SDF Import
Customer
Invoice
Search
Historical Data
```

## Phase 3 — Payment

```text
Cash
Transfer
Cheque
Payment Allocation
Partial Payment
Multi Invoice
```

## Phase 4 — OCR

```text
Image
PDF
Gemini
Structured OCR
Text Extraction
Fallback Model
```

## Phase 5 — Dashboard

```text
Daily Revenue
Payment
Outstanding
Reports
```

## Phase 6 — Realtime / Audit

```text
Realtime
Audit Log
Conflict Handling
```

---

# 38. Important Business Rules

1. ห้ามลบ Payment ที่มีการ Match แล้วแบบ Hard Delete
2. การแก้ Payment ต้องสร้าง Audit Log
3. Invoice ที่ Paid แล้วต้องไม่ถูก Match ซ้ำ
4. Payment หนึ่งรายการสามารถ Match หลาย Invoice ได้
5. Invoice หนึ่งใบสามารถมี Payment หลายรายการได้
6. Outstanding ต้องคำนวณจาก Allocation ไม่ใช่ให้ User กรอกเอง
7. Payment ที่ยอดไม่ตรงต้องมีเหตุผล
8. ทุก Attachment ต้องมีความสัมพันธ์กับ Record
9. Import SDF ต้องป้องกัน Duplicate
10. ทุก Transaction สำคัญต้องมี Created By / Created At
11. การแก้ไขข้อมูลสำคัญต้องมี Old Value / New Value
12. Realtime เป็นเพียงกลไก Sync ไม่ใช่ตัวแทนของ Database Transaction

---

# 39. Recommended Core Data Relationship

```text
CUSTOMER
   │
   ├──── INVOICE
   │       │
   │       └──── PAYMENT ALLOCATION
   │                    │
   │                    └──── PAYMENT
   │                              │
   │                              └──── ATTACHMENT
   │
   └──── PAYMENT
```

Relationship สำคัญที่สุดคือ

```text
Payment
    ↕
Payment Allocation
    ↕
Invoice
```

เพราะทำให้รองรับได้ทั้ง

```text
1 Payment → 1 Invoice
1 Payment → Multiple Invoice
Multiple Payment → 1 Invoice
```

---

# 40. Final Architecture

```text
                    ┌──────────────────┐
                    │   Web Browser    │
                    │ HTML/CSS/JS      │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
         Supabase        Supabase       Gemini AI
         Database        Storage        OCR
              │              │              │
              └──────────────┼──────────────┘
                             │
                       Supabase
                       Realtime
                             │
                ┌────────────┴────────────┐
                │                         │
             Device A                 Device B
```

## MVP Technology Stack

```text
Frontend
HTML5
Modern CSS
Vanilla JavaScript

Backend
Supabase

Database
PostgreSQL

Authentication
Supabase Auth

File Storage
Supabase Storage

Realtime
Supabase Realtime

Server Logic
Supabase Edge Functions

AI
Gemini / Gemma

Import
Express SDF Parser

Deployment
Static Web Hosting + Supabase
```

## หลักการสำคัญของระบบ

```text
Express SDF
     ↓
Invoice Database
     ↓
Customer Outstanding
     ↓
Payment
     ↓
AI OCR (ถ้าเป็น Slip)
     ↓
Payment Matching
     ↓
Payment Allocation
     ↓
Invoice Outstanding Update
     ↓
Dashboard
     ↓
Realtime Sync
     ↓
Audit Log
```

ระบบนี้ควรออกแบบโดยให้ **Invoice เป็นข้อมูลต้นทางของหนี้ และ Payment Allocation เป็นตัวกลางในการตัดยอด** แทนการแก้ `paid_amount` ของ Invoice โดยตรง วิธีนี้จะทำให้รองรับ Partial Payment, จ่ายหลายบิล, แบ่งจ่าย, ยอดเกิน และตรวจสอบย้อนหลังได้อย่างถูกต้องในระยะยาว