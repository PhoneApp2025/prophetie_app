const admin = require("firebase-admin");
admin.initializeApp();

const functions = require("firebase-functions");
const analyzeModule = require("./analyze");
exports.analyzeTraum = analyzeModule.analyzeTraum;
exports.analyzeProphetie = analyzeModule.analyzeProphetie;

const { onRequest } = require("firebase-functions/v2/https");
const express = require("express");
const fetch = require("node-fetch");

// Load Apple IAP shared secret from environment
const secret = process.env.IAP_SECRET;

const app = express();
// Parse raw JSON and strip control characters before parsing
app.use(express.json({ limit: '10mb' }));

// Cloud Run health check
app.get("/", (req, res) => {
    res.status(200).send("OK");
});

// Apple Receipt Verification 2025 Ready
app.post("/", async (req, res) => {
    console.log("verifyReceipt called");

    // Firebase ID Token aus dem Authorization Header prüfen
    const authHeader = req.get('Authorization') || '';
    const match = authHeader.match(/^Bearer (.*)$/);
    if (!match) {
        console.log("No Authorization header or invalid format");
        return res.status(401).send('Unauthorized');
    }
    const idToken = match[1];

    try {
        await admin.auth().verifyIdToken(idToken);
        console.log("ID Token valid");
    } catch (e) {
        console.log("ID Token verification failed", e);
        return res.status(401).send('Unauthorized');
    }

    const jsonBody = req.body;
    const receiptData = jsonBody["receipt-data"];
    const jsonReceipt = jsonBody["json-receipt"];
    if ((!receiptData || typeof receiptData !== "string" || receiptData.length < 10) && !jsonReceipt) {
        console.log("No or invalid receipt-data or json-receipt in body");
        return res.status(400).send("Missing or invalid receipt-data");
    }
    if (jsonReceipt) {
        console.log("Receipt received as JSON receipt");
    } else {
        console.log("Receipt received (first 40):", receiptData.slice(0, 40));
    }

    if (!secret) {
        console.log("Missing IAP_SECRET env var");
        return res.status(500).send("Server misconfiguration");
    }

    let payload;
    if (jsonReceipt) {
        // JSON (StoreKit2) receipt
        payload = { receipt: jsonReceipt, password: secret };
    } else {
        // Base64 receipt
        payload = { "receipt-data": receiptData, password: secret };
    }
    const headers = { "Content-Type": "application/json" };

    let appleEndpoint = "https://buy.itunes.apple.com/verifyReceipt"; // Default: Prod
    let response;
    let json;

    // Erst an Production
    try {
        console.log("Sending to Apple PROD endpoint.");
        response = await fetch(
            appleEndpoint,
            { method: "POST", headers, body: JSON.stringify(payload) }
        );
        json = await response.json();
        console.log("Apple PROD response:", json);
    } catch (e) {
        console.log("Error verifying production receipt:", e);
        return res.status(500).send("Error verifying receipt");
    }

    // 21007 = Sandbox-Receipt wurde an Production geschickt -> an Sandbox weiterleiten
    if (json.status === 21007) {
        appleEndpoint = "https://sandbox.itunes.apple.com/verifyReceipt";
        try {
            console.log("Sending to Apple SANDBOX endpoint.");
            response = await fetch(
                appleEndpoint,
                { method: "POST", headers, body: JSON.stringify(payload) }
            );
            json = await response.json();
            console.log("Apple SANDBOX response:", json);
        } catch (e) {
            console.log("Error verifying sandbox receipt:", e);
            return res.status(500).send("Error verifying sandbox receipt");
        }
    }

    // Fehlercode 21002 abfangen: ungültiges Format/Base64
    if (json.status === 21002) {
        console.log("Apple Error 21002: The receipt-data property was malformed or missing.");
        return res.status(400).json({ status: 21002, message: "Malformed or invalid receipt-data. See Apple docs." });
    }

    // Ergebnis zurück an App
    console.log("Sending response to app:", json);
    res.status(200).json(json);
});

exports.verifyReceipt = onRequest(app);

const { onCall } = require("firebase-functions/v2/https");

/**
 * Setzt den Status eines gesendeten Recordings beim Sender auf 'angenommen'.
 * Erwartet: data.senderUid (string), data.docId (string)
 * 
 * Beispiel-Aufruf aus Flutter:
 * FirebaseFunctions.instance.httpsCallable('markSentRecordingAccepted')
 *    .call({'senderUid': 'XYZ', 'docId': 'ABC'});
 */
exports.markSentRecordingAccepted = onCall(async (request) => {
    const senderUid = request.data.senderUid;
    const docId = request.data.docId;

    if (!request.auth || !request.auth.uid) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht eingeloggt.');
    }
    if (!senderUid || !docId) {
        throw new functions.https.HttpsError('invalid-argument', 'Fehlende senderUid oder docId.');
    }

    const docRef = admin.firestore()
        .collection('users').doc(senderUid)
        .collection('gesendet').doc(docId);

    const docSnap = await docRef.get();
    if (!docSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Das gesendete Recording existiert nicht.');
    }

    await docRef.update({ status: 'angenommen' });
    return { success: true };
});
