const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { Pool } = require('pg');
const cors = require('cors');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const multer = require('multer');
const fs = require('fs');

const app = express();
const server = http.createServer(app);

// ==================== Middleware ====================
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cors({
    origin: "*",
    methods: ["GET", "POST", "PUT", "DELETE"],
    allowedHeaders: ["Content-Type", "Authorization"]
}));

// Logging middleware
app.use((req, res, next) => {
    if (req.method === 'PUT' || req.method === 'POST' || req.method === 'DELETE') {
        console.log(`\n🚨=== [إشعار طلب جديد] ===🚨`);
        console.log(`🌐 الرابط: ${req.originalUrl}`);
        console.log(`📝 النوع: ${req.method}`);
        console.log(`📦 البيانات:`, JSON.stringify(req.body, null, 2));
        console.log(`📁 الملف:`, req.file ? req.file.filename : 'لا يوجد ملف');
        console.log(`================================\n`);
    }
    next();
});

// ==================== Create Directories ====================
const dirs = ['uploads', 'uploads_file', 'uploads_camera', 'uploads_office', 'uploads_reports', 'uploads_tickets'];
dirs.forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
        console.log(`✅ Created folder: ${dir}`);
    }
});

// ==================== Multer Configurations ====================
const storage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, 'uploads/'); },
    filename: (req, file, cb) => { cb(null, Date.now() + "-" + file.originalname); }
});
const upload = multer({ storage, limits: { fileSize: 5 * 1024 * 1024, fieldSize: 10 * 1024 * 1024 } });

const voiceStorage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, 'uploads/'); },
    filename: (req, file, cb) => {
        let ext = path.extname(file.originalname);
        if (!ext || ext === '') {
            if (file.mimetype === 'audio/webm' || file.mimetype === 'audio/opus') ext = '.opus';
            else if (file.mimetype === 'audio/aac') ext = '.aac';
            else if (file.mimetype === 'audio/mp4' || file.mimetype === 'audio/x-m4a') ext = '.m4a';
            else ext = '.webm';
        }
        cb(null, 'voice_' + Date.now() + ext);
    }
});
const uploadVoice = multer({ storage: voiceStorage });

const cameraStorage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, 'uploads_camera/'); },
    filename: (req, file, cb) => { cb(null, "camera-" + Date.now() + "-" + file.originalname); }
});
const uploadCamera = multer({ storage: cameraStorage });

const fileStorage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, 'uploads_file/'); },
    filename: (req, file, cb) => { cb(null, Date.now() + "-" + file.originalname); }
});
const uploadFile = multer({ storage: fileStorage });

const officeImageStorage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, 'uploads_office/'); },
    filename: (req, file, cb) => { cb(null, 'office_' + Date.now() + '-' + file.originalname); }
});
const uploadOfficeImage = multer({ storage: officeImageStorage });

const reportsStorage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, 'uploads_reports/'); },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, 'report_' + uniqueSuffix + path.extname(file.originalname));
    }
});
const uploadReport = multer({ storage: reportsStorage, limits: { fileSize: 10 * 1024 * 1024 } });

const ticketStorage = multer.diskStorage({
    destination: (req, file, cb) => { cb(null, 'uploads_tickets/'); },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, 'ticket_' + uniqueSuffix + path.extname(file.originalname));
    }
});
const uploadTicket = multer({ storage: ticketStorage, limits: { fileSize: 10 * 1024 * 1024 } });

// ==================== Static folders ====================
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/uploads_file', express.static(path.join(__dirname, 'uploads_file')));
app.use('/uploads_camera', express.static(path.join(__dirname, 'uploads_camera')));
app.use('/uploads_office', express.static(path.join(__dirname, 'uploads_office')));
app.use('/uploads_reports', express.static(path.join(__dirname, 'uploads_reports')));
app.use('/uploads_tickets', express.static(path.join(__dirname, 'uploads_tickets')));

// ==================== PostgreSQL ====================
// ✅ تم التعديل هنا: استخدام متغير البيئة DATABASE_URL بدلاً من البيانات الثابتة
const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: {
        rejectUnauthorized: false // ضروري للاتصال بـ Supabase
    }
});
app.use(express.static(path.join(__dirname, 'build/web')));

// ==================== Database initialization ====================
async function initializeDatabase() {
    const client = await pool.connect();
    try {
        await client.query(`
            CREATE TABLE IF NOT EXISTS groups (
                id UUID PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                icon TEXT,
                created_by UUID REFERENCES users(id) ON DELETE SET NULL,
                locked BOOLEAN DEFAULT false,
                created_at TIMESTAMP DEFAULT NOW()
            )
        `);
        await client.query(`
            CREATE TABLE IF NOT EXISTS group_members (
                id UUID PRIMARY KEY,
                group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                role VARCHAR(50) DEFAULT 'member',
                joined_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(group_id, user_id)
            )
        `);
        await client.query(`
            CREATE TABLE IF NOT EXISTS deleted_messages (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                deleted_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(message_id, user_id)
            )
        `);
        try {
            await client.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS chat_type VARCHAR(20) DEFAULT 'individual'`);
        } catch (err) {}
        try {
            await client.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT true`);
            console.log("✅ Column 'active' added/verified");
        } catch (err) {
            console.log("⚠️ Could not add 'active' column (may already exist):", err.message);
        }
        try {
            await client.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_message_id TEXT`);
            console.log("✅ Column 'reply_to_message_id' added/verified");
        } catch (err) {
            console.log("⚠️ Could not add 'reply_to_message_id':", err.message);
        }
        try {
            await client.query(`ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to JSONB`);
            console.log("✅ Column 'reply_to' added/verified");
        } catch (err) {
            console.log("⚠️ Could not add 'reply_to':", err.message);
        }

        await client.query(`
            CREATE TABLE IF NOT EXISTS office_status (
                id UUID PRIMARY KEY,
                office_name VARCHAR(255) NOT NULL,
                shift VARCHAR(20) NOT NULL CHECK (shift IN ('morning', 'evening')),
                owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
                status VARCHAR(50) NOT NULL CHECK (status IN ('working', 'problem', 'closed')),
                problem_type TEXT[],
                problem_details TEXT,
                image_url TEXT,
                image_urls TEXT[] DEFAULT '{}',
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(office_name, shift)
            )
        `);
        await client.query(`
            CREATE TABLE IF NOT EXISTS office_status_history (
                id UUID PRIMARY KEY,
                office_name VARCHAR(255) NOT NULL,
                shift VARCHAR(20),
                owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
                status VARCHAR(50) NOT NULL,
                problem_type TEXT[],
                problem_details TEXT,
                image_url TEXT,
                image_urls TEXT[] DEFAULT '{}',
                action VARCHAR(20) NOT NULL CHECK (action IN ('create', 'update', 'delete', 'auto_close')),
                changed_at TIMESTAMP DEFAULT NOW(),
                changed_by UUID REFERENCES users(id) ON DELETE SET NULL
            )
        `);
        console.log("✅ Database tables initialized with shift support and multiple images");

        await client.query(`
            CREATE TABLE IF NOT EXISTS reports (
                id UUID PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                description TEXT NOT NULL,
                status VARCHAR(50) DEFAULT 'new',
                attachments TEXT[] DEFAULT '{}',
                link TEXT,
                created_by UUID REFERENCES users(id) ON DELETE SET NULL,
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        `);
        console.log("✅ Table 'reports' created/verified");

        await client.query(`
            CREATE TABLE IF NOT EXISTS maintenance_tickets (
                id UUID PRIMARY KEY,
                user_id UUID REFERENCES users(id) ON DELETE SET NULL,
                maintenance_type VARCHAR(20) NOT NULL CHECK (maintenance_type IN ('site', 'device')),
                governorate VARCHAR(100) NOT NULL,
                work_location TEXT NOT NULL,
                date DATE NOT NULL,
                problem_description TEXT NOT NULL,
                site_issue TEXT,
                device_type VARCHAR(100),
                serial_number VARCHAR(100),
                device_name VARCHAR(100),
                device_location TEXT,
                attachments TEXT[] DEFAULT '{}',
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        `);
        console.log("✅ Table 'maintenance_tickets' created/verified");

        await client.query(`
            CREATE TABLE IF NOT EXISTS call_history (
                id UUID PRIMARY KEY,
                caller_id UUID REFERENCES users(id) ON DELETE CASCADE,
                receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
                status VARCHAR(20) NOT NULL CHECK (status IN ('missed', 'accepted', 'rejected', 'no_answer', 'busy', 'cancelled')),
                created_at TIMESTAMP DEFAULT NOW()
            )
        `);
        console.log("✅ Table 'call_history' verified");

    } catch (err) {
        console.error("❌ Error initializing database:", err.message);
    } finally {
        client.release();
    }
}
initializeDatabase();

// ==================== Online users & active calls ====================
const onlineUsers = new Map();
const activeCalls = new Map();
const processedCalls = new Set();

// ==================== Helper Functions ====================

function isValidUUID(str) {
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    return uuidRegex.test(str);
}

// ===== إرسال call_end إلى جميع sockets الخاصة بالمستخدم عبر الـ Room =====
function sendCallEndToUser(userId, callId, reason) {
    console.log(`[DEBUG][sendCallEndToUser] Called for userId=${userId}, callId=${callId}, reason=${reason}`);
    const endPayload = { callId, reason };
    
    console.log(`[DEBUG][sendCallEndToUser] Emitting to room user:${userId}`);
    io.to(`user:${userId}`).emit('call_end', endPayload);
    
    let foundViaDirect = false;
    io.sockets.sockets.forEach(socket => {
        if (socket.userId === userId || socket.handshake?.query?.userId === userId) {
            console.log(`[DEBUG][sendCallEndToUser] Found direct socket for ${userId}: ${socket.id}, emitting directly.`);
            socket.emit('call_end', endPayload);
            foundViaDirect = true;
        }
    });
    if (!foundViaDirect) {
        console.log(`[DEBUG][sendCallEndToUser] ⚠️ No direct socket found for userId=${userId}`);
    }
    console.log(`[DEBUG][sendCallEndToUser] Finished sending call_end to ${userId}`);
}

// ===== Helper: Insert call log message =====
async function insertCallLogMessage(chatId, callerId, receiverId, status, duration) {
    console.log(`[DEBUG][insertCallLogMessage] chatId=${chatId}, status=${status}`);
    if (!chatId) {
        console.warn('⚠️ insertCallLogMessage: chatId غير موجودة');
        return;
    }
    const messageData = {
        callerId,
        receiverId,
        status,
        duration: duration || 0
    };
    const messageJson = JSON.stringify(messageData);
    const msgId = uuidv4();
    try {
        await pool.query(
            `INSERT INTO messages (id, chat_id, sender_id, message, type, created_at)
             VALUES ($1, $2::uuid, $3::uuid, $4, 'call_log', NOW())`,
            [msgId, chatId.toString(), callerId, messageJson]
        );
        console.log(`📞 Call log inserted: ${status} for chat ${chatId}`);
        
        const inserted = await pool.query(`SELECT * FROM messages WHERE id = $1`, [msgId]);
        let messageRow = inserted.rows[0];
        io.to(chatId.toString()).emit('message', messageRow);
    } catch (err) {
        console.error('❌ Failed to insert call log:', err.message);
    }
}

// ===== Helper: clear active call timer =====
function clearActiveCallTimer(id1, id2) {
    console.log(`[DEBUG][clearActiveCallTimer] For ${id1} and ${id2}`);
    const callData = activeCalls.get(id1) || activeCalls.get(id2);
    if (callData && callData.timer) {
        clearTimeout(callData.timer);
        console.log(`[DEBUG][clearActiveCallTimer] Cleared timer for callId=${callData.callId}`);
        if (activeCalls.has(id1)) {
            activeCalls.set(id1, { ...activeCalls.get(id1), timer: null });
        }
        if (activeCalls.has(id2)) {
            activeCalls.set(id2, { ...activeCalls.get(id2), timer: null });
        }
    } else {
        console.log(`[DEBUG][clearActiveCallTimer] No timer found for ${id1} or ${id2}`);
    }
}

// ===== Helper: handle missed call =====
async function handleMissedCall(callId, callerId, receiverId, chatId) {
    console.log(`[CALL][handleMissedCall] callId=${callId}, caller=${callerId}, receiver=${receiverId}, chatId=${chatId}`);
    
    if (processedCalls.has(callId)) {
        console.log(`[CALL][handleMissedCall] Call ${callId} already processed, skipping.`);
        return;
    }
    processedCalls.add(callId);
    
    // إرسال إشارات الفائتة
    sendCallEndToUser(callerId, callId, 'missed');
    sendCallEndToUser(receiverId, callId, 'missed');
    io.to(`user:${receiverId}`).emit('missed_call', { callId, callerId, chatId });
    io.to(`user:${callerId}`).emit('call_no_answer', { callId, receiverId, chatId });
    console.log(`📞 Missed call end sent to both parties`);

    // تنظيف الذاكرة
    activeCalls.delete(callerId);
    activeCalls.delete(receiverId);

    // حفظ السجل
    try {
        let validCallId = callId;
        if (!isValidUUID(callId)) {
            validCallId = uuidv4();
            console.log(`⚠️ Invalid UUID format for missed call: ${callId}, using new UUID: ${validCallId}`);
        }
        await pool.query(
            `INSERT INTO call_history (id, caller_id, receiver_id, status) VALUES ($1, $2::uuid, $3::uuid, 'missed')`,
            [validCallId, callerId, receiverId]
        );
        if (chatId) {
            await insertCallLogMessage(chatId, callerId, receiverId, 'missed', 0);
        }
        console.log(`✅ Missed call history saved for chatId: ${chatId}`);
    } catch (err) {
        console.error("❌ Error in handleMissedCall:", err.message);
    } finally {
        processedCalls.delete(callId);
    }
}

// ===== Helper: finalize call and save history (معدلة لحماية التكرار) =====
async function finalizeCall(callId, callerId, receiverId, chatId, status, duration = 0) {
    console.log(`[CALL][finalizeCall] START: callId=${callId}, caller=${callerId}, receiver=${receiverId}, chatId=${chatId}, status=${status}, duration=${duration}`);

    // ✅ التحقق من التكرار أولاً (قبل أي إجراء)
    if (processedCalls.has(callId)) {
        console.log(`⚠️ Call ${callId} already processed, skipping.`);
        return;
    }
    processedCalls.add(callId);

    // 1. إرسال call_end للطرفين
    console.log(`[CALL][finalizeCall] Sending call_end to caller (${callerId}) and receiver (${receiverId})`);
    sendCallEndToUser(callerId, callId, status);
    sendCallEndToUser(receiverId, callId, status);
    console.log(`📞 call_end sent to ${callerId} and ${receiverId}`);

    // 2. تنظيف الذاكرة والمؤقتات
    clearActiveCallTimer(callerId, receiverId);
    activeCalls.delete(callerId);
    activeCalls.delete(receiverId);

    // 3. حفظ السجل
    try {
        let validCallId = callId;
        if (!isValidUUID(callId)) {
            validCallId = uuidv4();
            console.log(`⚠️ Invalid UUID format for callId: ${callId}, using new UUID: ${validCallId}`);
        }
        await pool.query(
            `INSERT INTO call_history (id, caller_id, receiver_id, status) VALUES ($1, $2::uuid, $3::uuid, $4)`,
            [validCallId, callerId, receiverId, status]
        );
        if (chatId) {
            await insertCallLogMessage(chatId, callerId, receiverId, status, duration);
        }
        console.log(`📞 Call history saved: ${status}, callId=${callId} (saved as ${validCallId})`);
    } catch (err) {
        console.error("❌ Error saving call history:", err.message);
    } finally {
        processedCalls.delete(callId);
        console.log(`[CALL][finalizeCall] END for callId=${callId}`);
    }
}

// ==================== API Routes ====================

app.get('/health', (req, res) => { res.json({ status: "ok", message: "Server is healthy" }); });

// Call history endpoint
app.get('/api/calls/history/:userId', async (req, res) => {
    const { userId } = req.params;
    try {
        const result = await pool.query(`
            SELECT ch.*, 
                   u1.username as caller_name, u1.user_file as caller_avatar,
                   u2.username as receiver_name, u2.user_file as receiver_avatar
            FROM call_history ch
            JOIN users u1 ON ch.caller_id = u1.id
            JOIN users u2 ON ch.receiver_id = u2.id
            WHERE ch.caller_id = $1::uuid OR ch.receiver_id = $1::uuid
            ORDER BY ch.created_at DESC
        `, [userId]);
        
        res.json({ success: true, history: result.rows });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
});

// File upload endpoints
app.post('/chat/upload', upload.single('chat_file'), (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ message: "لم يتم اختيار ملف" });
        res.json({ status: "success", url: req.file.filename });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.post('/chat/upload_voice', uploadVoice.single('chat_file'), async (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ message: "لم يتم اختيار ملف صوتي" });
        const { chat_id, sender_id, duration } = req.body;
        const msgId = uuidv4();
        const result = await pool.query(
            `INSERT INTO messages (id, chat_id, sender_id, message, type, duration, chat_type, created_at) 
             VALUES ($1, $2::uuid, $3::uuid, $4, 'voice', $5, 'group', NOW()) RETURNING *`,
            [msgId, chat_id, sender_id, req.file.filename, duration ? parseInt(duration) : 0]
        );
        io.to(chat_id.toString()).emit("message", result.rows[0]);
        res.json({ status: "success", url: req.file.filename, message: result.rows[0] });
    } catch (err) { console.error(err); res.status(500).json({ message: err.message }); }
});

app.post('/camera/upload', uploadCamera.single('camera_file'), (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ message: "لم يتم التقاط صورة" });
        res.json({ status: "success", url: "uploads_camera/" + req.file.filename });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.post('/user/upload_file', uploadFile.single('user_file'), (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ message: "لم يتم اختيار ملف" });
        res.json({ status: "success", url: req.file.filename });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

// User routes
app.post('/users/signup', async (req, res) => {
    const { username, email, phone, job, password, permissions, user_file } = req.body;
    try {
        const result = await pool.query(
            `INSERT INTO users (id, username, email, phone, job, password, permissions, user_file, created_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW()) RETURNING *`,
            [uuidv4(), username, email, phone, job, password, permissions || [], user_file || null]
        );
        res.json(result.rows[0]);
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.post('/users/login', async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ message: "missing" });
    try {
        const result = await pool.query('SELECT * FROM users WHERE email=$1 AND password=$2 LIMIT 1', [email, password]);
        if (result.rows.length === 0) return res.status(401).json({ message: "wrong" });
        const user = result.rows[0];
        await pool.query(`UPDATE users SET is_online = true WHERE id = $1::uuid`, [user.id]);
        res.json({ user });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.post('/users/update_status', async (req, res) => {
    const { user_id, is_online } = req.body;
    if (!user_id) return res.status(400).json({ message: "user_id مطلوب" });
    try {
        await pool.query(
            `UPDATE users SET is_online = $1, last_seen = CASE WHEN $1 = false THEN NOW() ELSE last_seen END WHERE id = $2::uuid`,
            [is_online, user_id]
        );
        res.json({ message: "تم تحديث الحالة" });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.post('/users/update_active', async (req, res) => {
    const { user_id, active_status } = req.body;
    if (!user_id) return res.status(400).json({ message: "user_id مطلوب" });
    try {
        await pool.query(`UPDATE users SET active = $1 WHERE id = $2::uuid`, [active_status, user_id]);
        res.json({ message: "تم تحديث الحالة اليدوية" });
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
});

app.get('/users', async (req, res) => {
    const result = await pool.query('SELECT id, username, email, avatar_url, job, phone, is_online, last_seen, active, permissions FROM users ORDER BY created_at DESC');
    res.json(result.rows);
});

app.get('/users/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query('SELECT id, username, avatar_url, job, phone, email, active FROM users WHERE id = $1::uuid', [id]);
        if (result.rows.length === 0) return res.status(404).json({ message: "المستخدم غير موجود" });
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
});

app.get('/users/status', async (req, res) => {
    try {
        const result = await pool.query('SELECT id, is_online, last_seen FROM users');
        res.json(result.rows);
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.delete('/users/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query('DELETE FROM users WHERE id = $1::uuid RETURNING *', [id]);
        if (result.rows.length === 0) return res.status(404).json({ message: "المستخدم غير موجود" });
        res.json({ message: "تم حذف المستخدم بنجاح" });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.put('/users/:id', async (req, res) => {
    const { id } = req.params;
    const { username, email, phone, job, role, permissions, password, user_file } = req.body;
    try {
        let result;
        if (password && password.trim() !== "") {
            result = await pool.query(
                `UPDATE users SET username=$1, email=$2, phone=$3, job=$4, role=$5, permissions=$6, password=$7, user_file=$8 WHERE id=$9::uuid RETURNING *`,
                [username, email, phone, job, role, permissions || [], password, user_file || null, id]
            );
        } else {
            result = await pool.query(
                `UPDATE users SET username=$1, email=$2, phone=$3, job=$4, role=$5, permissions=$6, user_file=$7 WHERE id=$8::uuid RETURNING *`,
                [username, email, phone, job, role, permissions || [], user_file || null, id]
            );
        }
        if (result.rows.length === 0) return res.status(404).json({ message: "المستخدم غير موجود" });
        res.json({ message: "تم التحديث بنجاح", user: result.rows[0] });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.post('/users/update_profile', upload.single('avatar'), async (req, res) => {
    try {
        if (!req.body || Object.keys(req.body).length === 0) {
            console.error("❌ req.body فارغ أو غير موجود");
            return res.status(400).json({ message: "لم يتم إرسال أي بيانات" });
        }

        const { id, username, job, phone, avatar_url } = req.body;
        let newUserFile = null;

        if (!id) {
            return res.status(400).json({ message: "معرف المستخدم مطلوب" });
        }

        if (req.file) {
            newUserFile = req.file.filename;
        }
        else if (avatar_url === "null" || avatar_url === "") {
            newUserFile = null;
        }
        else {
            const current = await pool.query(`SELECT user_file FROM users WHERE id = $1::uuid`, [id]);
            newUserFile = current.rows[0]?.user_file;
        }

        const result = await pool.query(
            `UPDATE users SET username=$1, job=$2, phone=$3, user_file=$4 WHERE id=$5::uuid RETURNING *`,
            [username, job, phone, newUserFile, id]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ message: "المستخدم غير موجود" });
        }

        const updatedUser = result.rows[0];
        updatedUser.avatar_url = updatedUser.user_file;

        res.json({ message: "تم التحديث", user: updatedUser });
    } catch (err) {
        console.error("Update profile error:", err);
        res.status(500).json({ message: err.message });
    }
});

// Reports Endpoints
app.post('/reports/upload', uploadReport.array('attachments', 10), (req, res) => {
    try {
        if (!req.files || req.files.length === 0) {
            return res.status(400).json({ success: false, message: "لم يتم رفع أي ملف" });
        }
        const filePaths = req.files.map(file => '/uploads_reports/' + file.filename);
        res.json({ success: true, files: filePaths });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
});

app.post('/reports/create', async (req, res) => {
    const { title, description, created_by, attachments, link } = req.body;
    if (!title || !description || !created_by) {
        return res.status(400).json({ success: false, message: "Missing required fields" });
    }
    try {
        const id = uuidv4();
        const attachmentsArray = attachments ?? [];
        const result = await pool.query(
            `INSERT INTO reports (id, title, description, status, attachments, link, created_by, created_at, updated_at)
             VALUES ($1, $2, $3, 'new', $4, $5, $6, NOW(), NOW()) RETURNING *`,
            [id, title, description, attachmentsArray, link || null, created_by]
        );
        res.json({ success: true, report: result.rows[0] });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.get('/reports/all', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT r.*, u.username as creator_name
            FROM reports r
            LEFT JOIN users u ON r.created_by = u.id
            ORDER BY r.created_at DESC
        `);
        res.json({ success: true, reports: result.rows });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.get('/reports/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query(`SELECT * FROM reports WHERE id = $1::uuid`, [id]);
        if (result.rows.length === 0) return res.status(404).json({ success: false, message: "Report not found" });
        res.json({ success: true, report: result.rows[0] });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
});

app.put('/reports/update/:id', async (req, res) => {
    const { id } = req.params;
    const { title, description, status, attachments, link } = req.body;
    try {
        const result = await pool.query(
            `UPDATE reports SET title=$1, description=$2, status=$3, attachments=$4, link=$5, updated_at=NOW()
             WHERE id=$6::uuid RETURNING *`,
            [title, description, status, attachments ?? [], link || null, id]
        );
        if (result.rows.length === 0) return res.status(404).json({ success: false, message: "Report not found" });
        res.json({ success: true, report: result.rows[0] });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
});

app.delete('/reports/delete/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query(`DELETE FROM reports WHERE id = $1::uuid RETURNING id`, [id]);
        if (result.rowCount === 0) return res.status(404).json({ success: false, message: "Report not found" });
        res.json({ success: true, message: "تم حذف التبليغ" });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
});

// Maintenance Tickets Endpoints
app.post('/api/tickets/create', uploadTicket.array('attachments', 10), async (req, res) => {
    try {
        const {
            userId,
            maintenanceType,
            problemDescription,
            governorate,
            workLocation,
            date,
            siteIssue,
            deviceType,
            serialNumber,
            deviceName,
            deviceLocation
        } = req.body;

        if (!userId || !maintenanceType || !problemDescription || !governorate || !workLocation || !date) {
            return res.status(400).json({ success: false, message: "Missing required fields" });
        }
        if (maintenanceType === 'site' && !siteIssue) {
            return res.status(400).json({ success: false, message: "Site issue is required" });
        }
        if (maintenanceType === 'device' && (!deviceType || !serialNumber)) {
            return res.status(400).json({ success: false, message: "Device fields (deviceType, serialNumber) are required" });
        }

        const id = uuidv4();
        let attachmentsPaths = [];
        if (req.files && req.files.length > 0) {
            attachmentsPaths = req.files.map(file => '/uploads_tickets/' + file.filename);
        }

        const query = `
            INSERT INTO maintenance_tickets (
                id, user_id, maintenance_type, governorate, work_location, date,
                problem_description, site_issue, device_type, serial_number, device_name, device_location, attachments, created_at, updated_at
            ) VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())
            RETURNING *
        `;
        const values = [
            id, userId, maintenanceType, governorate, workLocation, date,
            problemDescription, siteIssue || null, deviceType || null, serialNumber || null,
            deviceName || null, deviceLocation || null, attachmentsPaths
        ];

        const result = await pool.query(query, values);
        res.json({ success: true, ticket: result.rows[0] });
    } catch (err) {
        console.error("❌ Error creating maintenance ticket:", err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.get('/api/tickets/list', async (req, res) => {
    const { type, userId } = req.query;
    if (!userId) {
        return res.status(400).json({ success: false, message: "userId is required" });
    }
    try {
        let query = `
            SELECT t.*, u.username as user_name
            FROM maintenance_tickets t
            LEFT JOIN users u ON t.user_id = u.id
            WHERE t.user_id = $1::uuid
        `;
        const values = [userId];
        if (type === 'site') {
            query += ` AND t.maintenance_type = 'site'`;
        } else if (type === 'device') {
            query += ` AND t.maintenance_type = 'device'`;
        }
        query += ` ORDER BY t.created_at DESC`;

        const result = await pool.query(query, values);
        res.json({ success: true, tickets: result.rows });
    } catch (err) {
        console.error("❌ Error fetching tickets:", err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.get('/api/tickets/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query(`SELECT * FROM maintenance_tickets WHERE id = $1::uuid`, [id]);
        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, message: "Ticket not found" });
        }
        res.json({ success: true, ticket: result.rows[0] });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
});

app.delete('/api/tickets/delete/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const checkResult = await pool.query(`SELECT id FROM maintenance_tickets WHERE id = $1::uuid`, [id]);
        if (checkResult.rows.length === 0) {
            return res.status(404).json({ success: false, message: "التذكرة غير موجودة" });
        }
        const deleteResult = await pool.query(`DELETE FROM maintenance_tickets WHERE id = $1::uuid RETURNING id`, [id]);
        if (deleteResult.rowCount === 0) {
            return res.status(500).json({ success: false, message: "فشل حذف التذكرة" });
        }
        res.json({ success: true, message: "تم حذف التذكرة بنجاح" });
    } catch (err) {
        console.error("❌ Error deleting maintenance ticket:", err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.post('/users/status', async (req, res) => {
    if (!req.body || typeof req.body !== 'object') {
        return res.status(400).json({ success: false, message: "Missing request body" });
    }

    const user_id = req.body.user_id;
    const is_online = req.body.is_online;

    if (!user_id) {
        return res.status(400).json({ success: false, message: "user_id is required" });
    }

    try {
        const result = await pool.query(
            `UPDATE users SET is_online = $1, last_seen = NOW() WHERE id = $2::uuid RETURNING *`,
            [is_online, user_id]
        );
        
        if (result.rowCount === 0) {
            return res.status(404).json({ success: false, message: "User not found" });
        }

        return res.json({ success: true, message: "Status updated", user: result.rows[0] });
    } catch (err) {
        console.error("❌ Error in status route:", err.message);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// Conversations
app.post('/conversations/get_or_create', async (req, res) => {
    const { current_user_id, other_user_id } = req.body;
    try {
        const existing = await pool.query(`
            SELECT c.id FROM conversations c
            JOIN conversation_members m1 ON c.id = m1.conversation_id
            JOIN conversation_members m2 ON c.id = m2.conversation_id
            WHERE m1.user_id=$1::uuid AND m2.user_id=$2::uuid AND c.is_group=false
            LIMIT 1
        `, [current_user_id, other_user_id]);
        if (existing.rows.length > 0) return res.json(existing.rows[0]);
        const newConv = await pool.query('INSERT INTO conversations (id,is_group,created_at) VALUES ($1,false,NOW()) RETURNING id', [uuidv4()]);
        const convId = newConv.rows[0].id;
        await pool.query('INSERT INTO conversation_members (id,conversation_id,user_id) VALUES ($1,$2,$3),($4,$2,$5)', [uuidv4(), convId, current_user_id, uuidv4(), other_user_id]);
        res.json({ id: convId });
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.post('/conversations/get_or_create_with_details', async (req, res) => {
    const { current_user_id, other_user_id } = req.body;
    if (!current_user_id || !other_user_id) {
        return res.status(400).json({ success: false, error: "Missing user IDs" });
    }
    try {
        const existing = await pool.query(`
            SELECT c.id FROM conversations c
            JOIN conversation_members m1 ON c.id = m1.conversation_id
            JOIN conversation_members m2 ON c.id = m2.conversation_id
            WHERE m1.user_id=$1::uuid AND m2.user_id=$2::uuid AND c.is_group=false
            LIMIT 1
        `, [current_user_id, other_user_id]);
        if (existing.rows.length > 0) {
            const userInfo = await pool.query(
                `SELECT id, username, avatar_url, is_online, last_seen FROM users WHERE id = $1::uuid`,
                [other_user_id]
            );
            return res.json({
                success: true,
                conversation_id: existing.rows[0].id,
                is_new: false,
                user: userInfo.rows[0] || null
            });
        }
        const convId = uuidv4();
        await pool.query('INSERT INTO conversations (id, is_group, created_at) VALUES ($1, false, NOW())', [convId]);
        await pool.query(
            `INSERT INTO conversation_members (id, conversation_id, user_id) VALUES 
             ($1, $2, $3::uuid),
             ($4, $2, $5::uuid)`,
            [uuidv4(), convId, current_user_id, uuidv4(), other_user_id]
        );
        const userInfo = await pool.query(
            `SELECT id, username, avatar_url, is_online, last_seen FROM users WHERE id = $1::uuid`,
            [other_user_id]
        );
        res.json({
            success: true,
            conversation_id: convId,
            is_new: true,
            user: userInfo.rows[0] || null
        });
    } catch (err) {
        console.error("❌ Error in get_or_create_with_details:", err.message);
        res.status(500).json({ success: false, error: err.message });
    }
});

app.post('/messages/forward', async (req, res) => {
    const { chat_id, sender_id, message, type, chat_type, duration, original_sender, reply_to_message_id } = req.body;
    const msgId = uuidv4();
    if (!chat_id || !sender_id || !message) {
        return res.status(400).json({ success: false, error: "Missing required fields" });
    }
    try {
        const result = await pool.query(
            `INSERT INTO messages (id, chat_id, sender_id, message, type, chat_type, duration, reply_to_message_id, created_at) 
             VALUES ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8, NOW()) RETURNING *`,
            [msgId, chat_id, sender_id, message, type || 'text', chat_type || 'private', duration || null, reply_to_message_id || null]
        );
        const storedMessage = result.rows[0];
        storedMessage.forwarded = true;
        const roomName = String(chat_id).trim();
        io.to(roomName).emit("message", storedMessage);
        return res.json({ success: true, message: storedMessage });
    } catch (err) {
        console.error("❌ Forward error:", err.message);
        return res.status(500).json({ success: false, error: err.message });
    }
});

app.get('/chats/:user_id', async (req, res) => {
    const { user_id } = req.params;
    try {
        const result = await pool.query(`
            SELECT 
                c.id as chat_id,
                u.id as id,
                u.username,
                u.avatar_url as icon,
                u.job,
                u.is_online,
                u.active,
                u.permissions,
                COALESCE(u.last_seen::text, '') as last_seen,
                m.message as last_message,
                m.created_at as last_time
            FROM conversations c
            JOIN conversation_members cm ON c.id = cm.conversation_id
            JOIN conversation_members cm2 ON c.id = cm2.conversation_id AND cm2.user_id != $1::uuid
            JOIN users u ON u.id = cm2.user_id
            LEFT JOIN LATERAL (
                SELECT message, created_at
                FROM messages
                WHERE chat_id::text = c.id::text
                ORDER BY created_at DESC
                LIMIT 1
            ) m ON true
            WHERE cm.user_id = $1::uuid
            ORDER BY m.created_at DESC NULLS LAST
        `, [user_id]);
        res.json(result.rows);
    } catch (err) { res.status(500).json({ message: err.message }); }
});

app.get('/messages/get/:message_id', async (req, res) => {
    const { message_id } = req.params;
    try {
        const result = await pool.query(
            `SELECT id, message, type, sender_id, created_at, duration, chat_type
             FROM messages
             WHERE id = $1::uuid`,
            [message_id]
        );
        if (result.rows.length === 0) return res.status(404).json({ error: "Message not found" });
        res.json(result.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: err.message });
    }
});

app.get('/messages/:chat_id', async (req, res) => {
    const { chat_id } = req.params;
    const { user_id } = req.query;

    if (!user_id) {
        return res.status(400).json({ message: "user_id is required" });
    }

    try {
        const result = await pool.query(
            `SELECT m.* FROM messages m
             LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_id = $2::uuid
             WHERE m.chat_id = $1 AND dm.id IS NULL
             ORDER BY m.created_at ASC`,
            [chat_id, user_id]
        );
        
        let messages = result.rows;

        const replyToIds = messages.filter(m => m.reply_to_message_id && m.reply_to_message_id.trim() !== '').map(m => m.reply_to_message_id);
        if (replyToIds.length > 0) {
            const repliedMessages = await pool.query(
                `SELECT id, message, type, sender_id, created_at, duration, chat_type
                 FROM messages
                 WHERE id = ANY($1::uuid[])`,
                [replyToIds]
            );
            const replyMap = new Map();
            for (const rm of repliedMessages.rows) {
                replyMap.set(rm.id, rm);
            }
            for (const msg of messages) {
                if (msg.reply_to_message_id) {
                    msg.replied_message = replyMap.get(msg.reply_to_message_id) || null;
                }
            }
        }

        messages = messages.map(messageRow => {
            if (messageRow.type === 'call_log') {
                try {
                    const callData = typeof messageRow.message === 'string' ? JSON.parse(messageRow.message) : messageRow.message;
                    const isCaller = user_id === callData.callerId;
                    let displayStatus = 'مكالمة';

                    if (callData.status === 'missed') {
                        displayStatus = isCaller ? 'مكالمة صادرة' : 'مكالمة فائتة';
                    } else if (callData.status === 'accepted') {
                        displayStatus = isCaller ? 'مكالمة صادرة' : 'مكالمة مستلمة';
                    } else if (callData.status === 'cancelled') {
                        displayStatus = isCaller ? 'مكالمة ملغاة' : 'مكالمة فائتة';
                    } else if (callData.status === 'busy') {
                        displayStatus = isCaller ? 'مكالمة صادرة' : 'خط مشغول';
                    } else if (callData.status === 'rejected') {
                        displayStatus = isCaller ? 'مكالمة صادرة' : 'مكالمة مرفوضة';
                    }

                    messageRow.call_display_status = displayStatus;
                    messageRow.is_caller = isCaller;
                } catch (e) {
                    console.error("❌ Error parsing call_log message JSON", e);
                }
            }
            return messageRow;
        });

        res.json(messages);

    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

// GROUP ENDPOINTS
app.post('/groups/create', async (req, res) => {
    console.log("📥 /groups/create body:", req.body);
    const { name, members, created_by, icon } = req.body;
    const groupId = uuidv4();
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query(
            `INSERT INTO groups (id, name, icon, created_by, created_at) VALUES ($1, $2, $3, $4::uuid, NOW())`,
            [groupId, name, icon || null, created_by]
        );
        let insertedCount = 0;
        for (const userId of members) {
            const role = userId === created_by ? 'admin' : 'member';
            try {
                await client.query(
                    `INSERT INTO group_members (id, group_id, user_id, role) VALUES ($1, $2, $3::uuid, $4)`,
                    [uuidv4(), groupId, userId, role]
                );
                insertedCount++;
            } catch (err) {
                console.error(`❌ Failed to insert member ${userId}:`, err.message);
            }
        }
        await client.query('COMMIT');
        console.log(`✅ Group created: ${groupId}, members inserted: ${insertedCount}/${members.length}`);
        res.status(201).json({ id: groupId, name, icon, members, created_by });
    } catch (err) {
        await client.query('ROLLBACK');
        console.error("❌ Transaction failed:", err);
        res.status(500).json({ message: err.message });
    } finally {
        client.release();
    }
});

app.get('/groups', async (req, res) => {
    const { user_id } = req.query;
    if (!user_id) return res.status(400).json({ message: "يجب تمرير user_id" });
    try {
        const result = await pool.query(`
            SELECT 
                g.id,
                g.name,
                g.icon,
                g.created_by,
                g.created_at,
                g.locked,
                COALESCE(
                    (SELECT ARRAY_AGG(user_id) FROM group_members WHERE group_id = g.id),
                    ARRAY[]::uuid[]
                ) AS participants,
                COALESCE(
                    (SELECT ARRAY_AGG(user_id) FROM group_members WHERE group_id = g.id AND role = 'admin'),
                    ARRAY[]::uuid[]
                ) AS admins,
                (SELECT message FROM messages WHERE chat_id::text = g.id::text ORDER BY created_at DESC LIMIT 1) AS last_message,
                (SELECT created_at FROM messages WHERE chat_id::text = g.id::text ORDER BY created_at DESC LIMIT 1) AS last_time
            FROM groups g
            WHERE EXISTS (
                SELECT 1 FROM group_members WHERE group_id = g.id AND user_id = $1::uuid
            )
            ORDER BY last_time DESC NULLS LAST
        `, [user_id]);
        const groups = result.rows.map(row => ({
            id: row.id,
            name: row.name,
            icon: row.icon,
            is_group: true,
            participants: row.participants || [],
            admins: row.admins || [],
            permissions: row.created_by === user_id ? ["admin"] : [],
            currentMessage: row.last_message || "",
            time: row.last_time ? new Date(row.last_time).toISOString() : "",
            isOnline: false,
            lastSeen: "",
            status: "group",
            created_by: row.created_by,
            locked: row.locked || false
        }));
        res.json(groups);
    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

app.put('/groups/:group_id', async (req, res) => {
    const { group_id } = req.params;
    const { name, icon, requester_id } = req.body;
    if (!requester_id) return res.status(400).json({ message: "requester_id مطلوب" });
    try {
        const group = await pool.query(`SELECT created_by FROM groups WHERE id = $1`, [group_id]);
        if (group.rows.length === 0) return res.status(404).json({ message: "المجموعة غير موجودة" });
        const isCreator = group.rows[0].created_by === requester_id;
        const memberRole = await pool.query(
            `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`,
            [group_id, requester_id]
        );
        const isAdmin = isCreator || (memberRole.rows[0]?.role === 'admin');
        if (!isAdmin) return res.status(403).json({ message: "غير مصرح" });
        let query = 'UPDATE groups SET ';
        const updates = [];
        const values = [];
        if (name) {
            updates.push(`name = $${values.length + 1}`);
            values.push(name);
        }
        if (icon) {
            updates.push(`icon = $${values.length + 1}`);
            values.push(icon);
        }
        if (updates.length === 0) return res.status(400).json({ message: "لا توجد بيانات للتحديث" });
        query += updates.join(', ') + ` WHERE id = $${values.length + 1}`;
        values.push(group_id);
        await pool.query(query, values);
        res.json({ message: "تم التحديث بنجاح" });
    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

app.post('/groups/add_members', async (req, res) => {
    const { group_id, member_ids, requester_id } = req.body;
    if (!group_id || !Array.isArray(member_ids) || member_ids.length === 0) {
        return res.status(400).json({ message: "بيانات غير صحيحة" });
    }
    if (!requester_id) return res.status(400).json({ message: "requester_id مطلوب" });
    try {
        const group = await pool.query(`SELECT created_by FROM groups WHERE id = $1`, [group_id]);
        if (group.rows.length === 0) return res.status(404).json({ message: "المجموعة غير موجودة" });
        const isCreator = group.rows[0].created_by === requester_id;
        const memberRole = await pool.query(
            `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`,
            [group_id, requester_id]
        );
        const isAdmin = isCreator || (memberRole.rows[0]?.role === 'admin');
        if (!isAdmin) return res.status(403).json({ message: "غير مصرح" });
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            for (const userId of member_ids) {
                const existing = await client.query(
                    `SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`,
                    [group_id, userId]
                );
                if (existing.rows.length === 0) {
                    await client.query(
                        `INSERT INTO group_members (id, group_id, user_id, role) VALUES ($1, $2, $3::uuid, 'member')`,
                        [uuidv4(), group_id, userId]
                    );
                }
            }
            await client.query('COMMIT');
            for (const userId of member_ids) {
                await client.query(`
                    DELETE FROM deleted_messages
                    WHERE user_id = $1::uuid
                    AND message_id IN (SELECT id FROM messages WHERE chat_id::text = $2)
                `, [userId, group_id]);
            }
            res.json({ message: "تمت إضافة الأعضاء بنجاح" });
        } catch (err) {
            await client.query('ROLLBACK');
            throw err;
        } finally {
            client.release();
        }
    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

app.post('/groups/remove_member', async (req, res) => {
    const { group_id, user_id, requester_id } = req.body;
    if (!group_id || !user_id || !requester_id) return res.status(400).json({ message: "بيانات ناقصة" });
    try {
        const group = await pool.query(`SELECT created_by FROM groups WHERE id = $1`, [group_id]);
        if (group.rows.length === 0) return res.status(404).json({ message: "المجموعة غير موجودة" });
        const isCreator = group.rows[0].created_by === requester_id;
        const memberRole = await pool.query(
            `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`,
            [group_id, requester_id]
        );
        const isAdmin = isCreator || (memberRole.rows[0]?.role === 'admin');
        if (!isAdmin) return res.status(403).json({ message: "غير مصرح" });
        if (user_id === group.rows[0].created_by) {
            return res.status(400).json({ message: "لا يمكن طرد منشئ المجموعة" });
        }
        await pool.query(`DELETE FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`, [group_id, user_id]);
        io.to(group_id).emit("member_removed", { group_id, user_id });
        res.json({ message: "تم طرد العضو" });
    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

app.post('/groups/promote_admin', async (req, res) => {
    const { group_id, user_id, requester_id } = req.body;
    if (!group_id || !user_id || !requester_id) return res.status(400).json({ message: "بيانات ناقصة" });
    try {
        const group = await pool.query(`SELECT created_by FROM groups WHERE id = $1`, [group_id]);
        if (group.rows.length === 0) return res.status(404).json({ message: "المجموعة غير موجودة" });
        const isCreator = group.rows[0].created_by === requester_id;
        const memberRole = await pool.query(
            `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`,
            [group_id, requester_id]
        );
        const isAdmin = isCreator || (memberRole.rows[0]?.role === 'admin');
        if (!isAdmin) return res.status(403).json({ message: "غير مصرح" });
        if (user_id === group.rows[0].created_by) {
            return res.status(400).json({ message: "المنشئ هو مشرف بالفعل" });
        }
        await pool.query(
            `UPDATE group_members SET role = 'admin' WHERE group_id = $1 AND user_id = $2::uuid`,
            [group_id, user_id]
        );
        io.to(group_id).emit("member_promoted", { group_id, user_id });
        res.json({ message: "تمت الترقية إلى مشرف" });
    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

app.delete('/groups/:group_id', async (req, res) => {
    const { group_id } = req.params;
    const { requester_id } = req.body;
    if (!requester_id) return res.status(400).json({ message: "requester_id مطلوب" });
    try {
        const group = await pool.query(`SELECT created_by FROM groups WHERE id = $1`, [group_id]);
        if (group.rows.length === 0) return res.status(404).json({ message: "المجموعة غير موجودة" });
        const isCreator = group.rows[0].created_by === requester_id;
        const memberRole = await pool.query(
            `SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`,
            [group_id, requester_id]
        );
        const isAdmin = isCreator || (memberRole.rows[0]?.role === 'admin');
        if (!isAdmin) return res.status(403).json({ message: "غير مصرح" });
        await pool.query(`DELETE FROM groups WHERE id = $1`, [group_id]);
        io.to(group_id).emit("group_deleted", { group_id });
        res.json({ message: "تم حذف المجموعة" });
    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

app.post('/groups/leave', async (req, res) => {
    const { group_id, user_id } = req.body;
    if (!group_id || !user_id) return res.status(400).json({ message: "بيانات ناقصة" });
    try {
        await pool.query(`
            DELETE FROM deleted_messages
            WHERE user_id = $1::uuid
            AND message_id IN (SELECT id FROM messages WHERE chat_id::text = $2)
        `, [user_id, group_id]);
        await pool.query(`DELETE FROM group_members WHERE group_id = $1 AND user_id = $2::uuid`, [group_id, user_id]);
        res.json({ message: "تمت المغادرة بنجاح" });
    } catch (err) {
        console.error(err);
        res.status(500).json({ message: err.message });
    }
});

// Office management endpoints
app.post('/office/upload_image', uploadOfficeImage.single('office_image'), (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ success: false, message: "لم يتم اختيار صورة" });
        const imageUrl = '/uploads_office/' + req.file.filename;
        res.json({ success: true, image_url: imageUrl });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
});

app.get('/office/status', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT id, office_name, shift, owner_id, status, problem_type, problem_details, image_url, image_urls, created_at, updated_at
            FROM office_status
            ORDER BY office_name ASC, shift ASC
        `);
        res.json({ success: true, data: result.rows });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.get('/office/history', async (req, res) => {
    const { office_name, shift } = req.query;
    try {
        let query = `SELECT * FROM office_status_history`;
        const params = [];
        const conditions = [];
        if (office_name) {
            conditions.push(`office_name = $${params.length + 1}`);
            params.push(office_name);
        }
        if (shift && (shift === 'morning' || shift === 'evening')) {
            conditions.push(`shift = $${params.length + 1}`);
            params.push(shift);
        }
        if (conditions.length > 0) {
            query += ' WHERE ' + conditions.join(' AND ');
        }
        query += ' ORDER BY changed_at DESC';
        const result = await pool.query(query, params);
        res.json({ success: true, data: result.rows });
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.post('/office/status', uploadOfficeImage.single('office_image'), async (req, res) => {
    try {
        let { office_name, shift, status, problem_type, problem_details, user_id, image_urls } = req.body;
        let singleImageUrl = req.body.image_url;
        let newImageUrl = singleImageUrl || null;
        let imageUrlsArray = [];

        if (image_urls) {
            try {
                imageUrlsArray = Array.isArray(image_urls) ? image_urls : JSON.parse(image_urls);
            } catch(e) { imageUrlsArray = []; }
        }
        if (req.file) {
            const uploadedUrl = '/uploads_office/' + req.file.filename;
            imageUrlsArray.push(uploadedUrl);
            newImageUrl = uploadedUrl;
        }

        if (!office_name || !shift || !status || !user_id) {
            return res.status(400).json({ success: false, message: "Missing required fields" });
        }
        if (!['morning', 'evening'].includes(shift)) {
            return res.status(400).json({ success: false, message: "shift must be morning or evening" });
        }
        if (status === 'problem' && (!problem_type || problem_type.length === 0)) {
            return res.status(400).json({ success: false, message: "يجب تحديد نوع المشكلة" });
        }

        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            const otherShift = shift === 'morning' ? 'evening' : 'morning';
            const otherExisting = await client.query(
                `SELECT * FROM office_status WHERE office_name = $1 AND shift = $2`,
                [office_name, otherShift]
            );
            if (otherExisting.rows.length > 0) {
                const otherRecord = otherExisting.rows[0];
                await client.query(
                    `INSERT INTO office_status_history (id, office_name, shift, owner_id, status, problem_type, problem_details, image_url, image_urls, action, changed_at, changed_by)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'delete', NOW(), $10)`,
                    [uuidv4(), office_name, otherShift, otherRecord.owner_id, otherRecord.status,
                     otherRecord.problem_type, otherRecord.problem_details, otherRecord.image_url,
                     otherRecord.image_urls, user_id]
                );
                await client.query(
                    `DELETE FROM office_status WHERE office_name = $1 AND shift = $2`,
                    [office_name, otherShift]
                );
            }

            const existing = await client.query(
                `SELECT * FROM office_status WHERE office_name = $1 AND shift = $2`,
                [office_name, shift]
            );
            let action = '';
            let parsedProblemType = problem_type ? (Array.isArray(problem_type) ? problem_type : JSON.parse(problem_type)) : null;
            let newProblemDetails = problem_details || null;

            if (existing.rows.length === 0) {
                action = 'create';
                await client.query(
                    `INSERT INTO office_status (id, office_name, shift, owner_id, status, problem_type, problem_details, image_url, image_urls, created_at, updated_at)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())`,
                    [uuidv4(), office_name, shift, user_id, status, parsedProblemType, newProblemDetails, newImageUrl, imageUrlsArray]
                );
            } else {
                const record = existing.rows[0];
                if (record.owner_id !== user_id) {
                    const user = await client.query(`SELECT role FROM users WHERE id = $1::uuid`, [user_id]);
                    const isAdmin = (user.rows[0]?.role === 'manager' || user.rows[0]?.role === 'admin');
                    if (!isAdmin) {
                        await client.query('ROLLBACK');
                        return res.status(403).json({ success: false, message: "غير مصرح لك بتعديل هذا المكتب" });
                    }
                }
                action = 'update';
                await client.query(
                    `UPDATE office_status
                     SET status = $1, problem_type = $2, problem_details = $3, image_url = $4, image_urls = $5, updated_at = NOW(), owner_id = $6
                     WHERE office_name = $7 AND shift = $8`,
                    [status, parsedProblemType, newProblemDetails, newImageUrl, imageUrlsArray, user_id, office_name, shift]
                );
            }

            await client.query(
                `INSERT INTO office_status_history (id, office_name, shift, owner_id, status, problem_type, problem_details, image_url, image_urls, action, changed_at, changed_by)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), $11)`,
                [uuidv4(), office_name, shift, user_id, status, parsedProblemType, newProblemDetails, newImageUrl, imageUrlsArray, action, user_id]
            );

            await client.query('COMMIT');
            res.json({ success: true, message: "تم حفظ الحالة بنجاح" });
        } catch (err) {
            await client.query('ROLLBACK');
            console.error(err);
            res.status(500).json({ success: false, message: err.message });
        } finally {
            client.release();
        }
    } catch (err) {
        console.error(err);
        res.status(500).json({ success: false, message: err.message });
    }
});

app.delete('/office/status/:office_name/:shift', async (req, res) => {
    const { office_name, shift } = req.params;
    const { user_id } = req.body;
    if (!user_id || !shift) {
        return res.status(400).json({ success: false, message: "user_id and shift required" });
    }
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const existing = await client.query(
            `SELECT * FROM office_status WHERE office_name = $1 AND shift = $2`,
            [office_name, shift]
        );
        if (existing.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ success: false, message: "المكتب غير موجود لهذا الشفت" });
        }
        const record = existing.rows[0];
        if (record.owner_id !== user_id) {
            const user = await client.query(`SELECT role FROM users WHERE id = $1::uuid`, [user_id]);
            const isAdmin = (user.rows[0]?.role === 'manager' || user.rows[0]?.role === 'admin');
            if (!isAdmin) {
                await client.query('ROLLBACK');
                return res.status(403).json({ success: false, message: "غير مصرح لك بحذف هذا المكتب" });
            }
        }
        await client.query(
            `INSERT INTO office_status_history (id, office_name, shift, owner_id, status, problem_type, problem_details, image_url, image_urls, action, changed_at, changed_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'delete', NOW(), $10)`,
            [uuidv4(), office_name, shift, record.owner_id, record.status, record.problem_type, record.problem_details, record.image_url, record.image_urls, user_id]
        );
        await client.query(`DELETE FROM office_status WHERE office_name = $1 AND shift = $2`, [office_name, shift]);
        await client.query('COMMIT');
        res.json({ success: true, message: "تم حذف المكتب لهذا الشفت بنجاح" });
    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ success: false, message: err.message });
    } finally {
        client.release();
    }
});

// ==================== Socket.io ====================
const io = new Server(server, {
    cors: { origin: "*" },
    pingTimeout: 10000,
    pingInterval: 5000,
    transports: ['websocket', 'polling']
});

io.on('connection', (socket) => {
    console.log('✅ New client connected:', socket.id);
    const userId = socket.handshake.query.userId || socket.handshake.auth?.userId;
    console.log(`[DEBUG][connection] Socket ${socket.id} initial userId from query: ${userId}`);

    socket.on("signin", async (userId) => {
        console.log(`[SIGNIN] Received signin from socket ${socket.id} with userId=${userId}`);
        if (!userId) {
            console.log(`[SIGNIN] ⚠️ userId missing, ignoring`);
            return;
        }
        socket.userId = userId;
        socket.join(`user:${userId}`);
        onlineUsers.set(userId, socket.id);
        console.log(`[SIGNIN] Socket ${socket.id} joined room user:${userId}, onlineUsers updated`);
        await pool.query(`UPDATE users SET is_online = true WHERE id = $1::uuid`, [userId]);
        socket.broadcast.emit("user_status", { user_id: userId, is_online: true, last_seen: "" });
        console.log(`📱 User registered for calls: ${userId} with socket: ${socket.id}`);
    });

    socket.on("ping", () => {
        if (socket.userId && onlineUsers.has(socket.userId)) {
            // update timestamp if needed
        }
    });

    socket.on("logout", async (userId) => {
        console.log(`[SIGNIN] logout received for userId=${userId} from socket ${socket.id}`);
        if (!userId) return;
        onlineUsers.delete(userId);
        if (activeCalls.has(userId)) {
            const callData = activeCalls.get(userId);
            if (callData && callData.timer) clearTimeout(callData.timer);
            const otherId = (callData.callerId === userId) ? callData.receiverId : callData.callerId;
            if (otherId) {
                sendCallEndToUser(otherId, callData.callId, 'user_logged_out');
                sendCallEndToUser(userId, callData.callId, 'user_logged_out');
            }
            for (let [uid, data] of activeCalls.entries()) {
                if (data.callId === callData.callId) {
                    activeCalls.delete(uid);
                }
            }
        }
        const result = await pool.query(`UPDATE users SET is_online = false, last_seen = NOW() WHERE id = $1::uuid RETURNING last_seen`, [userId]);
        socket.broadcast.emit("user_status", {
            user_id: userId,
            is_online: false,
            last_seen: result.rows[0]?.last_seen ? new Date(result.rows[0].last_seen).toISOString() : ""
        });
        socket.disconnect();
    });

    socket.on('disconnect', async () => {
        console.log(`[DEBUG][disconnect] Socket ${socket.id} disconnected, userId=${socket.userId}`);
        if (socket.userId) {
            onlineUsers.delete(socket.userId);
            console.log(`[DEBUG][disconnect] Removed userId=${socket.userId} from onlineUsers`);
            if (activeCalls.has(socket.userId)) {
                const callData = activeCalls.get(socket.userId);
                console.log(`[DEBUG][disconnect] Found active call for userId=${socket.userId}, callId=${callData?.callId}`);
                if (callData && callData.timer) clearTimeout(callData.timer);
                const otherId = (callData.callerId === socket.userId) ? callData.receiverId : callData.callerId;
                if (otherId) {
                    sendCallEndToUser(otherId, callData.callId, 'user_disconnected');
                    sendCallEndToUser(socket.userId, callData.callId, 'user_disconnected');
                }
                for (let [uid, data] of activeCalls.entries()) {
                    if (data.callId === callData.callId) {
                        activeCalls.delete(uid);
                    }
                }
            }
            try {
                const result = await pool.query(`UPDATE users SET is_online = false, last_seen = NOW() WHERE id = $1::uuid RETURNING last_seen`, [socket.userId]);
                socket.broadcast.emit("user_status", {
                    user_id: socket.userId,
                    is_online: false,
                    last_seen: result.rows[0]?.last_seen ? new Date(result.rows[0].last_seen).toISOString() : new Date().toISOString()
                });
            } catch (err) { console.error("Error updating status on disconnect:", err.message); }
        }
    });

    socket.on("join_chat", (chat_id) => {
        if (chat_id) {
            socket.join(chat_id.toString());
            console.log(`📌 Socket joined room ${chat_id}`);
        }
    });

    socket.on("message", async (data) => {
        console.log("📥 Incoming message data:", data);
        const { chat_id, sender_id, message, type, chat_type, reply_to_message_id } = data;
        const msgId = uuidv4();
        if (!chat_id || !sender_id || !message) {
            console.error("⚠️ Missing fields, message not saved");
            return;
        }
        try {
            const result = await pool.query(
                `INSERT INTO messages (id, chat_id, sender_id, message, type, chat_type, reply_to_message_id, created_at) 
                 VALUES ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, NOW()) RETURNING *`,
                [msgId, chat_id.toString(), sender_id, message, type || 'text', chat_type || 'private', reply_to_message_id || null]
            );
            console.log("✅ Message saved with ID:", result.rows[0].id);
            io.to(chat_id.toString()).emit("message", result.rows[0]);
        } catch (err) {
            console.error("❌ Error saving message:", err.message);
        }
    });

    socket.on("delete_message", async (data) => {
        const { message_id, chat_id } = data;
        try {
            await pool.query('DELETE FROM messages WHERE id = $1::uuid', [message_id]);
            io.to(chat_id.toString()).emit("message_deleted", message_id);
        } catch (err) { console.error(err); }
    });

    socket.on("delete_for_me", async (data) => {
        const { message_id, user_id } = data;
        try {
            await pool.query('INSERT INTO deleted_messages (message_id, user_id) VALUES ($1::uuid, $2::uuid) ON CONFLICT DO NOTHING', [message_id, user_id]);
        } catch (err) { console.error(err); }
    });

    // ==============================================
    // WebRTC Signaling - المعدل مع سجلات وإزالة الإرسال المباشر لـ call_reject
    // ==============================================
    
    socket.on("call_offer", (data) => {
        const { to, call_id, video, offer, caller_name, caller_avatar, chat_id } = data;
        console.log(`[CALL][call_offer] Received from socket ${socket.id}, to=${to}, call_id=${call_id}, chat_id=${chat_id}`);
        if (!to || !call_id || !offer) {
            console.error("❌ Invalid call_offer data");
            return;
        }

        if (activeCalls.has(to)) {
            console.log(`[CALL][call_offer] User ${to} is busy, sending call_busy`);
            socket.emit("call_busy", { 
                to: socket.userId, 
                call_id: call_id,
                message: "المستخدم مشغول حالياً" 
            });
            return;
        }

        const missedCallTimer = setTimeout(async () => {
            console.log(`[CALL][call_offer] Timer expired for callId=${call_id}, handling missed call`);
            await handleMissedCall(call_id, socket.userId, to, chat_id);
        }, 40000);

        const callInfo = {
            callId: call_id,
            callerId: socket.userId,
            receiverId: to,
            timer: missedCallTimer,
            chatId: chat_id,
            startTime: Date.now()
        };
        activeCalls.set(socket.userId, callInfo);
        activeCalls.set(to, callInfo);
        console.log(`[CALL][call_offer] activeCalls updated for ${socket.userId} and ${to}`);

        io.to(`user:${to}`).emit("call_offer", {
            from: socket.userId,
            call_id: call_id,
            video: video,
            offer: offer,
            caller_name: caller_name || 'مستخدم',
            caller_avatar: caller_avatar || '',
            chat_id: chat_id
        });
        console.log(`📞 Call offer from ${socket.userId} to ${to}, call_id: ${call_id}, chatId: ${chat_id}`);
    });

    socket.on("call_answer", (data) => {
        const { to, call_id, answer } = data;
        console.log(`[CALL][call_answer] Received from ${socket.id}, to=${to}, call_id=${call_id}`);
        if (!to || !call_id || !answer) {
            console.error("❌ Invalid call_answer data");
            return;
        }

        clearActiveCallTimer(socket.userId, to);

        const callData = activeCalls.get(socket.userId) || activeCalls.get(to);
        const chatId = callData?.chatId;

        io.to(`user:${to}`).emit("call_answer", {
            from: socket.userId,
            call_id: call_id,
            answer: answer,
            chat_id: chatId
        });
        console.log(`📞 Call answer from ${socket.userId} to ${to}, call_id: ${call_id}`);
    });

    socket.on("ice_candidate", (data) => {
        const { to, call_id, candidate } = data;
        console.log(`[CALL][ice_candidate] Received from ${socket.id}, to=${to}, call_id=${call_id}`);
        if (!to || !call_id || !candidate) {
            console.error("❌ Invalid ice_candidate data");
            return;
        }
        io.to(`user:${to}`).emit("ice_candidate", {
            from: socket.userId,
            call_id: call_id,
            candidate: candidate
        });
    });

    // ===== حدث رفض المكالمة (معدل - لا يرسل call_reject مباشرة) =====
    socket.on("call_reject", async (data) => {
        const { to, call_id } = data;
        console.log(`[CALL][call_reject] Received from socket ${socket.id}, to=${to}, call_id=${call_id}`);
        if (!to || !call_id) {
            console.error("❌ call_reject: بيانات ناقصة");
            return;
        }

        // ✅ تم إزالة الإرسال المباشر لـ call_reject، نكتفي بـ finalizeCall
        // io.to(`user:${to}`).emit("call_reject", { ... }); // مُعلق

        const callData = activeCalls.get(socket.userId) || activeCalls.get(to);
        if (!callData) {
            console.warn(`⚠️ call_reject: لا توجد مكالمة نشطة للـ call_id=${call_id}`);
            // نرسل call_end كحل احتياطي
            sendCallEndToUser(to, call_id, 'rejected');
            sendCallEndToUser(socket.userId, call_id, 'rejected');
            return;
        }

        const chatId = callData.chatId;
        const callerId = callData.callerId || socket.userId;
        const receiverId = callData.receiverId || to;

        console.log(`[CALL][call_reject] Finalizing call: callerId=${callerId}, receiverId=${receiverId}, chatId=${chatId}`);
        await finalizeCall(call_id, callerId, receiverId, chatId, 'rejected', 0);
    });

    // ===== حدث الانشغال =====
    socket.on("call_busy", async (data) => {
        const { to, call_id } = data;
        console.log(`[CALL][call_busy] Received from ${socket.id}, to=${to}, call_id=${call_id}`);
        if (!to || !call_id) return;

        const callData = activeCalls.get(socket.userId) || activeCalls.get(to);
        if (!callData) return;

        const chatId = callData.chatId;
        const callerId = callData.callerId || socket.userId;
        const receiverId = callData.receiverId || to;

        await finalizeCall(call_id, callerId, receiverId, chatId, 'busy', 0);
    });

    // ===== حدث إنهاء المكالمة من العميل =====
    socket.on('end_call', async (data) => {
        const { callId, callerId, receiverId, chatId, status, duration } = data;
        console.log(`[CALL][end_call] Received from socket ${socket.id}: callId=${callId}, status=${status}, chatId=${chatId}`);

        let finalDuration = duration || 0;
        if (status === 'accepted' && finalDuration === 0) {
            const callData = activeCalls.get(callerId) || activeCalls.get(receiverId);
            if (callData && callData.startTime) {
                finalDuration = Math.floor((Date.now() - callData.startTime) / 1000);
            }
        }

        await finalizeCall(callId, callerId, receiverId, chatId, status, finalDuration);
    });

    // ===== حدث خطأ المكالمة =====
    socket.on("call_error", (data) => {
        const { to, call_id, message } = data;
        console.log(`[CALL][call_error] Received from ${socket.id}, to=${to}, call_id=${call_id}`);
        if (!to || !call_id) return;
        io.to(`user:${to}`).emit("call_error", {
            from: socket.userId,
            call_id: call_id,
            message: message || "حدث خطأ في المكالمة"
        });
        if (activeCalls.has(socket.userId)) activeCalls.delete(socket.userId);
        if (activeCalls.has(to)) activeCalls.delete(to);
    });

    // ===== إضافة مستمع لحدث ice_gathering_complete =====
    socket.on("ice_gathering_complete", (data) => {
        const { to, call_id } = data;
        console.log(`[CALL][ice_gathering_complete] Received from ${socket.id}, to=${to}, call_id=${call_id}`);
        if (to && call_id) {
            io.to(`user:${to}`).emit("ice_gathering_complete", {
                from: socket.userId,
                call_id: call_id
            });
        }
    });
});

server.listen(5050, '0.0.0.0', () => {
    console.log("Scope_chats server running on port 5050");
});