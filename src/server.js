require('dotenv').config();
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const { Pool } = require('pg');
const bcrypt = require('bcrypt');
const { exec } = require('child_process');
const moment = require('moment');
const fs = require('fs');

const app = express();
const PORT = 80;
const WLAN = process.env.WLAN_IFACE || 'wlan0';

const pool = new Pool({
    user: process.env.DB_USER,
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    password: process.env.DB_PASS,
    port: process.env.DB_PORT,
});

app.set('view engine', 'ejs');
app.use(bodyParser.urlencoded({ extended: true }));
app.use(session({ secret: process.env.SESSION_SECRET || 'dev_secret', resave: false, saveUninitialized: true }));
app.use(express.static('public'));

function getIpFromMac(mac) {
    try {
        const leases = fs.readFileSync('/var/lib/misc/dnsmasq.leases', 'utf8');
        for (let line of leases.split('\n')) {
            const parts = line.split(' ');
            if (parts.length >= 3 && parts[1].toUpperCase() === mac.toUpperCase()) return parts[2];
        }
    } catch(e){}
    return null;
}

async function syncTrafficControl() {
    exec(`tc filter del dev ${WLAN} parent 1:0 2>/dev/null`);
    const result = await pool.query(`SELECT d.mac, u.bandwidth_mbps, u.id as uid FROM devices d JOIN users u ON d.user_id = u.id WHERE d.status = 'APPROVED' AND u.status = 'APPROVED'`);
    for (const r of result.rows) {
        const ip = getIpFromMac(r.mac);
        if (!ip) continue; 
        let classId = "1:10"; 
        if (r.bandwidth_mbps && r.bandwidth_mbps > 0) {
            classId = `1:1${r.uid.toString().padStart(3, '0')}`;
            exec(`tc class replace dev ${WLAN} parent 1:1 classid ${classId} htb rate ${r.bandwidth_mbps}mbit ceil ${r.bandwidth_mbps}mbit`);
        }
        exec(`tc filter add dev ${WLAN} protocol ip parent 1:0 prio 1 u32 match ip dst ${ip}/32 flowid ${classId}`);
        exec(`tc filter add dev ${WLAN} protocol ip parent 1:0 prio 1 u32 match ip src ${ip}/32 flowid ${classId}`);
    }
}

function unlockFirewall(mac) {
    exec(`iptables -t nat -I PREROUTING 1 -m mac --mac-source ${mac} -j ACCEPT`);
    exec(`iptables -I FORWARD 1 -m mac --mac-source ${mac} -j ACCEPT`);
    setTimeout(syncTrafficControl, 1500); 
}

function kickFirewall(mac) {
    exec(`iptables -D FORWARD -m mac --mac-source ${mac} -j ACCEPT`);
    exec(`iptables -t nat -D PREROUTING -m mac --mac-source ${mac} -j ACCEPT`);
    exec(`conntrack -D -m mac --mac-source ${mac} 2>/dev/null`);
    exec(`hostapd_cli deauthenticate ${mac}`);
}

function getMac(ip) {
    const cleanIp = ip.replace('::ffff:', '');
    return new Promise((resolve) => {
        exec(`ip neigh show ${cleanIp}`, (err, stdout) => {
            if (stdout.includes('lladdr')) resolve(stdout.split('lladdr')[1].trim().split(' ')[0].toUpperCase());
            else resolve(null);
        });
    });
}

setInterval(async () => {
    const now = moment().format('HH:mm:ss');
    const result = await pool.query(`SELECT u.id, u.username, u.start_time, u.end_time, d.mac FROM users u JOIN devices d ON u.id = d.user_id WHERE u.status = 'APPROVED' AND d.status = 'APPROVED' AND u.is_admin = false AND u.start_time IS NOT NULL AND u.end_time IS NOT NULL`);
    result.rows.forEach(r => { if (now < r.start_time || now > r.end_time) kickFirewall(r.mac); });
}, 60000);

app.use(async (req, res, next) => {
    const host = req.get('host');
    if (host !== process.env.DOMAIN && host !== process.env.GATEWAY_IP && !host.includes('localhost')) {
        return res.redirect(`http://${process.env.DOMAIN}`);
    }
    next();
});

app.get('/', (req, res) => res.render('login', { message: null }));
app.get('/register', (req, res) => res.render('register', { message: null }));
app.get('/guest', (req, res) => res.render('guest_login', { message: null }));

app.post('/login', async (req, res) => {
    const { username, password } = req.body;
    try {
        const result = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
        if (result.rows.length > 0) {
            const user = result.rows[0];
            if (await bcrypt.compare(password, user.password_hash)) {
                req.session.userId = user.id;
                req.session.isAdmin = user.is_admin;
                req.session.username = user.username;
                if (!user.is_admin && user.start_time && user.end_time) {
                    const now = moment().format('HH:mm:ss');
                    if (now < user.start_time || now > user.end_time) return res.render('login', { message: "Restricted Hours" });
                }
                const rawIp = req.ip.replace('::ffff:', '');
                exec(`ip neigh show ${rawIp}`, async (err, stdout) => {
                    let currentMac = null;
                    if (stdout.includes('lladdr')) currentMac = stdout.split('lladdr')[1].trim().split(' ')[0].toUpperCase();
                    if (user.is_admin && currentMac) await pool.query('INSERT INTO devices (user_id, mac, name, status) VALUES ($1, $2, $3, $4) ON CONFLICT (mac) DO NOTHING', [user.id, currentMac, 'Admin Session', 'APPROVED']);
                    const devices = await pool.query('SELECT mac FROM devices WHERE user_id = $1 AND status = $2', [user.id, 'APPROVED']);
                    devices.rows.forEach(d => unlockFirewall(d.mac));
                });
                return res.redirect('/dashboard');
            }
        }
        res.render('login', { message: "Invalid Credentials" });
    } catch { res.render('login', { message: "System Error" }); }
});

app.post('/guest_login', async (req, res) => {
    const { name, code } = req.body;
    const mac = await getMac(req.ip);
    if (!mac) return res.render('guest_login', { message: "Error: No MAC detected." });
    const voucher = await pool.query("SELECT * FROM vouchers WHERE code = $1 AND is_used = false", [code]);
    if(voucher.rows.length === 0) return res.render('guest_login', { message: "Invalid Code." });
    await pool.query("UPDATE vouchers SET is_used = true, expires_at = NOW() + interval '4 hours' WHERE id = $1", [voucher.rows[0].id]);
    const username = `Guest-${name.replace(/\s/g, '')}-${Math.floor(Math.random()*1000)}`;
    try {
        const hash = await bcrypt.hash(code, 10);
        const u = await pool.query("INSERT INTO users (username, password_hash, status, bandwidth_mbps) VALUES ($1, $2, 'APPROVED', 10) RETURNING id", [username, hash]);
        await pool.query("INSERT INTO devices (user_id, mac, name, status) VALUES ($1, $2, 'Guest Device', 'APPROVED')", [u.rows[0].id, mac]);
        unlockFirewall(mac);
        req.session.userId = u.rows[0].id;
        res.render('success', { message: "Welcome Guest! Access granted for 4 hours." });
    } catch(e) { res.render('guest_login', { message: "Error creating guest session." }); }
});

app.get('/dashboard', async (req, res) => {
    if (!req.session.userId) return res.redirect('/');
    if (req.session.isAdmin) return res.redirect('/admin');
    const user = await pool.query('SELECT * FROM users WHERE id = $1', [req.session.userId]);
    const devices = await pool.query('SELECT * FROM devices WHERE user_id = $1', [req.session.userId]);
    res.render('dashboard', { user: user.rows[0], devices: devices.rows, message: null });
});
app.post('/register', async (req, res) => {
    const { username, password } = req.body;
    const mac = await getMac(req.ip);
    try {
        const hash = await bcrypt.hash(password, 10);
        const u = await pool.query('INSERT INTO users (username, password_hash, status) VALUES ($1, $2, $3) RETURNING id', [username, hash, 'PENDING']);
        await pool.query('INSERT INTO devices (user_id, mac, name, status) VALUES ($1, $2, $3, $4)', [u.rows[0].id, mac, 'Primary', 'PENDING']);
        res.render('login', { message: "Account created! Waiting for Admin." });
    } catch { res.render('register', { message: "Username taken." }); }
});
app.post('/add_device', async (req, res) => {
    if (!req.session.userId) return res.redirect('/');
    try { await pool.query('INSERT INTO devices (user_id, mac, name, status) VALUES ($1, $2, $3, $4)', [req.session.userId, req.body.mac.trim().toUpperCase(), req.body.name, 'PENDING']); } catch (e) {}
    res.redirect('/dashboard');
});
app.post('/delete_device', async (req, res) => {
    if (!req.session.userId) return res.redirect('/');
    const check = await pool.query('SELECT mac FROM devices WHERE id = $1 AND user_id = $2', [req.body.deviceId, req.session.userId]);
    if(check.rows.length > 0) { kickFirewall(check.rows[0].mac); await pool.query('DELETE FROM devices WHERE id = $1', [req.body.deviceId]); }
    res.redirect('/dashboard');
});
app.get('/admin', async (req, res) => {
    if (!req.session.isAdmin) return res.redirect('/');
    const pendingUsers = await pool.query('SELECT * FROM users WHERE status = $1', ['PENDING']);
    const activeUsers = await pool.query('SELECT * FROM users WHERE status = $1 AND is_admin = false ORDER BY username ASC', ['APPROVED']);
    const pendingDevices = await pool.query('SELECT d.*, u.username FROM devices d JOIN users u ON d.user_id = u.id WHERE d.status = $1', ['PENDING']);
    const vouchers = await pool.query('SELECT * FROM vouchers WHERE is_used = false');
    res.render('admin', { pendingUsers: pendingUsers.rows, activeUsers: activeUsers.rows, pendingDevices: pendingDevices.rows, vouchers: vouchers.rows });
});
app.post('/admin/approve_user', async (req, res) => {
    if (!req.session.isAdmin) return res.sendStatus(403);
    await pool.query('UPDATE users SET status = $1 WHERE id = $2', ['APPROVED', req.body.userId]);
    await pool.query('UPDATE devices SET status = $1 WHERE user_id = $2', ['APPROVED', req.body.userId]);
    res.redirect('/admin');
});
app.post('/admin/approve_device', async (req, res) => {
    if (!req.session.isAdmin) return res.sendStatus(403);
    const res2 = await pool.query('UPDATE devices SET status = $1 WHERE id = $2 RETURNING mac', ['APPROVED', req.body.deviceId]);
    if(res2.rows.length > 0) unlockFirewall(res2.rows[0].mac);
    res.redirect('/admin');
});
app.post('/admin/update_user', async (req, res) => {
    if (!req.session.isAdmin) return res.sendStatus(403);
    const { userId, bandwidth, start, end } = req.body;
    const mbps = bandwidth ? parseInt(bandwidth) : null;
    const sTime = start ? start : null;
    const eTime = end ? end : null;
    await pool.query('UPDATE users SET bandwidth_mbps = $1, start_time = $2, end_time = $3 WHERE id = $4', [mbps, sTime, eTime, userId]);
    syncTrafficControl();
    res.redirect('/admin');
});
app.post('/admin/kick_user', async (req, res) => {
    if (!req.session.isAdmin) return res.sendStatus(403);
    await pool.query('UPDATE users SET status = $1 WHERE id = $2', ['PENDING', req.body.userId]);
    const devices = await pool.query('SELECT mac FROM devices WHERE user_id = $1', [req.body.userId]);
    devices.rows.forEach(d => kickFirewall(d.mac));
    res.redirect('/admin');
});
app.post('/admin/generate_voucher', async (req, res) => {
    if (!req.session.isAdmin) return res.sendStatus(403);
    await pool.query("INSERT INTO vouchers (code) VALUES ($1)", ["GUEST-" + Math.floor(1000 + Math.random() * 9000)]);
    res.redirect('/admin');
});

async function restoreState() {
    const result = await pool.query("SELECT mac FROM devices WHERE status = 'APPROVED'");
    result.rows.forEach(r => {
        exec(`iptables -t nat -I PREROUTING 1 -m mac --mac-source ${r.mac} -j ACCEPT`);
        exec(`iptables -I FORWARD 1 -m mac --mac-source ${r.mac} -j ACCEPT`);
    });
    setTimeout(syncTrafficControl, 2000);
}
app.listen(PORT, () => { console.log('Smart Home Server Started'); setTimeout(restoreState, 5000); });