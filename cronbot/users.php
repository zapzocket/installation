<?php

require_once '../config.php';
require_once '../function.php';
require_once '../botapi.php';

// Set headers and configuration
header('Content-Type: application/json; charset=UTF-8');
date_default_timezone_set('Asia/Tehran');
ini_set('default_charset', 'UTF-8');
ini_set('error_log', 'error_log');

/**
 * Utility Functions
 */
function sendJsonResponse($status, $message, $data = [], $httpCode = 200) {
    http_response_code($httpCode);
    echo json_encode([
        'status' => $status,
        'msg' => $message,
        'obj' => $data
    ], JSON_UNESCAPED_UNICODE);
    exit;
}


function validateToken($headers) {
    global $APIKEY;
    if (!isset($headers['Token'])) {
        return false;
    }
    
    $token = file_get_contents('hash.txt');
    $validTokens = [$token,$APIKEY];
    return in_array($headers['Token'], $validTokens, true);
}

function sanitizeRecursive($data) {
    if (is_array($data)) {
        return array_map('sanitizeRecursive', $data);
    }
    return is_string($data) ? htmlspecialchars(trim($data), ENT_QUOTES, 'UTF-8') : $data;
}

function validateMethod($expected, $actual) {
    if (strtoupper($expected) !== strtoupper($actual)) {
        sendJsonResponse(false, "method invalid; method must be {$expected}");
    }
}

function logApiRequest($headers, $data, $action) {
    global $pdo;
    
    try {
        $stmt = $pdo->prepare(
            "INSERT IGNORE INTO logs_api (header, data, time, ip, actions) VALUES (?, ?, ?, ?, ?)"
        );
        $stmt->execute([
            json_encode($headers),
            json_encode($data),
            date('Y/m/d H:i:s'),
            $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            $action
        ]);
    } catch (Exception $e) {
        error_log("API logging error: " . $e->getMessage());
    }
}

/**
 * Main API Logic
 */

// Get and validate headers
$headers = getallheaders();
if (!validateToken($headers)) {
    sendJsonResponse(false, "token invalid",[],403);
}

// Get request method and data
$method = $_SERVER['REQUEST_METHOD'];
$rawData = file_get_contents("php://input");
$data = json_decode($rawData, true);

// Validate JSON data
if (!is_array($data)) {
    sendJsonResponse(false, "data invalid", []);
}

// Sanitize input data
$data = sanitizeRecursive($data);

// Log API request
logApiRequest($headers, $data, $data['actions'] ?? 'unknown');

// Get settings
$setting = select("setting", "*");

// Route based on action
switch ($data['actions'] ?? '') {
    
    case 'users':
    validateMethod('GET', $method,[],403);

    // Validate and set limit
    $limit = 50;
    if (isset($data['limit']) && is_numeric($data['limit'])) {
        $limit = min(max((int)$data['limit'], 1), 1000);
    }

    // Validate and set page
    $page = isset($data['page']) && is_numeric($data['page']) ? max((int)$data['page'], 1) : 1;
    $offset = ($page - 1) * $limit;

    try {
        $stmt = $pdo->query("SELECT COUNT(*) as total FROM user");
        $totalUsers = (int) $stmt->fetchColumn();
        $totalPages = ceil($totalUsers / $limit);

        $stmt = $pdo->prepare("SELECT id as user_id,username,limit_usertest,roll_Status,number,Balance,User_Status,agent,affiliatescount,affiliates,cardpayment,register as time_join,verify,pricediscount FROM user LIMIT :limit OFFSET :offset");
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

        sendJsonResponse(true, "Successful", [
            'users' => $users,
            'pagination' => [
                'total_users' => $totalUsers,
                'total_pages' => $totalPages,
                'current_page' => $page,
                'per_page' => $limit
            ]
        ]);

    } catch (Exception $e) {
        error_log("Database error in users: " . $e->getMessage());
        sendJsonResponse(false, "Database error occurred", [], 500);
    }
    break;

    case 'user':
        validateMethod('GET', $method);
        
        // Validate chat_id
        if (!isset($data['chat_id']) || empty($data['chat_id'])) {
            sendJsonResponse(false, "chat_id empty", []);
        }
        
        try {
        $stmt = $pdo->prepare("SELECT id as user_id,username,limit_usertest,roll_Status,number,Balance,User_Status,agent,affiliatescount,affiliates,cardpayment,register as time_join,verify,pricediscount FROM user WHERE id = :user_id OR username = :username");
        $stmt->bindValue(':user_id',intval($data['chat_id']), PDO::PARAM_INT);
        $stmt->bindValue(':username',$data['chat_id'], PDO::PARAM_STR);
        $stmt->execute();
        $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $stmt = $pdo->prepare("SELECT SUM(price_product) as sum_price,COUNT(username) as count_invoice FROM invoice WHERE name_product != 'سرویس تست' AND  id_user = :user_id AND Status != 'Unpaid'");
        $stmt->bindValue(':user_id',intval($users[0]['user_id']), PDO::PARAM_INT);
        $stmt->execute();
        $invoice = $stmt->fetch(PDO::FETCH_ASSOC);
        $stmt = $pdo->prepare("SELECT SUM(price) as sum_price,COUNT(username) as count_invoice FROM service_other WHERE id_user = :user_id AND status != 'Unpaid'");
        $stmt->bindValue(':user_id',intval($users[0]['user_id']), PDO::PARAM_INT);
        $stmt->execute();
        $service_other = $stmt->fetch(PDO::FETCH_ASSOC);
        $users[0]['count_invoice'] = $invoice['count_invoice'] + $service_other['count_invoice'];
        $users[0]['sum_invoice'] = number_format($invoice['sum_price'] + intval($service_other['sum_price']));
        sendJsonResponse(true, "Successful", [
            'users' => $users,
            'pagination' => [
                'total_users' => 1,
                'total_pages' => 1,
                'current_page' => 1,
                'per_page' => 10
            ]
        ]);
        } catch (Exception $e) {
            error_log("Database error in user: " . $e->getMessage());
            sendJsonResponse(false, "Database error occurred",[],500);
        }
        break;
    
    case 'user_add':
        validateMethod('POST', $method);
        
        // Validate chat_id
        if (!isset($data['chat_id']) || empty($data['chat_id'])) {
            sendJsonResponse(false, "user-id empty",[],500);
        }
        
        // Get user info from Telegram
        try {
            $userInfo = telegram('getChat', ['chat_id' => $data['chat_id']]);
            
            if (!$userInfo['ok']) {
                sendJsonResponse(false, $userInfo['description'] ?? 'Telegram API error');
            }
            
            // Generate random invitation code
            $randomString = bin2hex(random_bytes(6));
            $currentTime = time();
            
            // Set verification status
            $verifyValue = ($setting['verifystart'] === "onverify") ? 0 : 1;
            
            // Prepare user data
            $userData = [
                'id' => $data['chat_id'],
                'step' => 'none',
                'limit_usertest' => $setting['limit_usertest_all'],
                'User_Status' => 'Active',
                'number' => 'none',
                'Balance' => '0',
                'pagenumber' => '1',
                'username' => $userInfo['result']['username'] ?? 'none',
                'agent' => 'f',
                'message_count' => '0',
                'last_message_time' => '0',
                'affiliates' => '0',
                'affiliatescount' => '0',
                'cardpayment' => $setting['showcard'],
                'number_username' => '100',
                'namecustom' => 'none',
                'register' => $currentTime,
                'verify' => $verifyValue,
                'codeInvitation' => $randomString,
                'pricediscount' => '0',
                'maxbuyagent' => '0',
                'joinchannel' => '0',
                'score' => '0'
            ];
            
            // Insert user into database
            $columns = implode(',', array_keys($userData));
            $placeholders = ':' . implode(', :', array_keys($userData));
            
            $stmt = $pdo->prepare(
                "INSERT IGNORE INTO user ({$columns}) VALUES ({$placeholders})"
            );
            
            foreach ($userData as $key => $value) {
                $stmt->bindValue(":{$key}", $value);
            }
            
            $stmt->execute();
            sendJsonResponse(true, "Successful");
            
        } catch (Exception $e) {
            error_log("Error in user_add: " . $e->getMessage());
            sendJsonResponse(false, "An error occurred while adding user");
        }
        break;
    
    default:
        sendJsonResponse(false, "Action Invalid");
        break;
}

?>