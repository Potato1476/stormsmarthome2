const express = require('express');
const http_module = require('http');
const iot_data = require('./iot_data').iot_data;
var sql = require('./iot-db');
var last_spout_log;
var last_storm_log;

// NOTE: Slack alerting was moved to the Gateway tier (fog-gateway Bolt_ingest →
// SlackNotifier), which detects anomalies on raw readings at the edge. The Cloud
// no longer sends Slack alerts — see RUNBOOK_ALERTS.md. The dashboard still shows
// the Cloud's own notification feed over websockets (below).

const app = express()
const port = 9000
var prefix = "";

app.use(express.static('public'))
app.use(express.json())

app.get('/api/query', (req, res) => {
    let queryParams = req.query;
    sql.query(new iot_data(queryParams.house_id, queryParams.household_id, queryParams.device_id, queryParams.year, queryParams.month, queryParams.day, queryParams.slice_gap, queryParams.slice_index), (err, result) => {
        if (err) res.status(500).json({ error: 'Database query failed' });
        else res.json(result);
    });
});

app.get('/api/getmeta', (req, res) => {
    let queryParams = req.query;
    sql.getMeta((err,result) => {
        if(err) res.status(500).send('Server error but it must be your fault');
        else res.json(result);
    });
})

app.get('/api/queryforecast', (req, res) => {
    let queryParams = req.query;
    sql.queryforecast(new iot_data(queryParams.house_id, queryParams.household_id, queryParams.device_id, queryParams.year, queryParams.month, queryParams.day, queryParams.slice_gap, queryParams.slice_index), queryParams.version || 'v1', (err, result) => {
        if (err) res.status(500).send('Server error but it must be your fault');
        else res.json(result);
    });
});

app.get('/api/querybyweek', (req, res) => {
    let queryParams = req.query;
    sql.querybyweek(new iot_data(queryParams.house_id, queryParams.year, queryParams.month, queryParams.day, queryParams.slice_gap, queryParams.slice_index), queryParams.week, (err, result) => {
        if (err) res.status(500).send('Server error but it must be your fault');
        else res.json(result);
    });
});

app.get('/api/queryforecastbyweek', (req, res) => {
    let queryParams = req.query;
    sql.queryforecastbyweek(new iot_data(queryParams.house_id, queryParams.year, queryParams.month, queryParams.day, queryParams.slice_gap, queryParams.slice_index), queryParams.week, queryParams.version || 'v1', (err, result) => {
        if (err) res.status(500).send('Server error but it must be your fault');
        else res.json(result);
    });
});

app.get('/api/getforecastmetadata', (req, res) => {
    let queryParams = req.query;
    sql.getforecastmetadata(queryParams.version, queryParams.slice_gap, (err, result) => {
        if (err) res.status(500).send('Server error but it must be your fault');
        else res.json(result[0]);
    });
})

app.get('/api/getdevicenotification', (req, res) => {
    let queryParams = req.query;
    sql.getdevicenotifications(queryParams.house_id, queryParams.household_id, queryParams.device_id, queryParams.offset || 0, queryParams.limit || 10, (err, result) => {
        if (err) res.status(500).send('Server error but it must be your fault');
        else res.json(result);
    })
})

app.get('/api/gethouseholdnotification', (req, res) => {
    let queryParams = req.query;
    sql.gethouseholdnotifications(queryParams.house_id, queryParams.household_id, queryParams.offset || 0, queryParams.limit || 10, (err, result) => {
        if (err) res.status(500).send('Server error but it must be your fault');
        else res.json(result);
    })
})

app.get('/api/gethousenotification', (req, res) => {
    let queryParams = req.query;
    sql.gethousenotifications(queryParams.house_id, queryParams.offset || 0, queryParams.limit || 10, (err, result) => {
        if (err) res.status(500).send('Server error but it must be your fault');
        else res.json(result);
    })
})

app.get('/', (req, res) => {
    res.sendFile(__dirname + '/public/index.html');
});



const server = require('http').createServer(app);
const io = require('socket.io')(server, {
    cors: {
      origin: '*',
      methods: ['GET', 'POST'],
      credentials: true
    }
});
io.on('connection', client => {
    console.log(`Client ${client.id}(${client.handshake.address}) connected`);
    client.join('iot-notification');
    client.join('storm-log');
    client.join('spout-log');
    if(last_storm_log) {
        client.emit('log', last_storm_log)
    }
    if(last_spout_log) {
        client.emit('spout', last_spout_log);
    }
    client.on('request', data => {
        try{
            let parsedData = JSON.parse(data);
            let topic = parsedData.topic;
            // Check permission
            mqttclient.subscribe(topic, function (err) {
                if (err) {
                    client.emit('error', JSON.stringify(err) );
                    console.log(err);
                }
                else{
                    client.join(topic);
                    console.log(`subscribed to mqtt ${topic} for client ${client.id}(${client.handshake.address})`);
                }
            });
        } catch (e){
            console.log(e);
            client.emit('error', JSON.stringify(e) );
        }
    });
    client.on('disconnect', () => {
        console.log(`Client ${client} disconnected!`);
    });
    client.on('error', (err)=>{
        console.log(`Client ${client.id}(${client.handshake.address}) get error (${err})`);
    })
});

// MQTT notification connect
var mqtt = require('mqtt');
const mqttHost = process.env.MQTT_BROKER_HOST || 'mqtt-broker';
const mqttPort = process.env.MQTT_BROKER_PORT || '1883';
var mqttclient = mqtt.connect(`mqtt://${mqttHost}:${mqttPort}`);
console.log(`[MQTT] Connecting to ${mqttHost}:${mqttPort}...`);

mqttclient.on('connect', function () {
    mqttclient.subscribe(prefix + 'iot-notification', function (err) {
        if (!err) {
            console.log(`subscribed to mqtt global notification channel`);
        }
    })
    mqttclient.subscribe(prefix + 'storm-log', function (err) {
        if (!err) {
            console.log(`subscribed to storm logging channel`);
        }
    })
    mqttclient.subscribe(prefix + 'spout-log', function (err) {
        if (!err) {
            console.log(`subscribed to spout logging channel`);
        }
    })
    mqttclient.on('message', function (topic, message) {
        // message is Buffer
        const msgStr = message.toString();
        switch(topic){
            case `${prefix}storm-log`:
                last_storm_log = msgStr;
                io.to('storm-log').emit('log', msgStr);
                break;
            case `${prefix}spout-log`:
                last_spout_log = msgStr;
                io.to('spout-log').emit('spout', msgStr);
                break;
            default:
                io.to(topic).emit('notification', msgStr);
        }
    });
})

server.listen(port, () => {
    console.log(`Web app listening on port ${port}!`);
})