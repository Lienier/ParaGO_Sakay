# ParaGO MySQL-Style Database Tables

> Presentation schema based on the current ParaGO MongoDB/Mongoose models. This format shows how the data would be represented as relational MySQL tables.

## 1. Users

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `user_id` | BIGINT | PK | No | User identifier |
| `email` | VARCHAR(255) | UNIQUE | No | Login email |
| `password_hash` | VARCHAR(255) |  | Yes | Encrypted password |
| `full_name` | VARCHAR(150) |  | No | Complete name |
| `phone` | VARCHAR(30) |  | Yes | Contact number |
| `role` | ENUM |  | No | PASSENGER, DRIVER, or ADMIN |
| `auth_provider` | ENUM |  | No | local, google, or facebook |
| `provider_id` | VARCHAR(255) |  | Yes | External provider ID |
| `status` | ENUM |  | No | active, suspended, deactivated |
| `is_verified` | BOOLEAN |  | No | Verification status |
| `last_login_at` | DATETIME |  | Yes | Last login time |
| `created_at` | DATETIME |  | No | Creation timestamp |
| `updated_at` | DATETIME |  | No | Last update timestamp |

## 2. Passengers

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `passenger_id` | BIGINT | PK | No | Passenger identifier |
| `user_id` | BIGINT | FK → users | No | Linked user account |
| `phone` | VARCHAR(30) |  | Yes | Passenger contact number |
| `photo_url` | VARCHAR(500) |  | Yes | Profile photo |
| `emergency_contact_name` | VARCHAR(150) |  | Yes | Emergency contact name |
| `emergency_contact_phone` | VARCHAR(30) |  | Yes | Emergency contact number |
| `default_route_id` | BIGINT | FK → routes | Yes | Preferred route |
| `created_at` | DATETIME |  | No | Creation timestamp |
| `updated_at` | DATETIME |  | No | Last update timestamp |

## 3. Drivers

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `driver_id` | BIGINT | PK | No | Driver identifier |
| `user_id` | BIGINT | FK → users | No | Linked user account |
| `license_number` | VARCHAR(80) |  | Yes | Driver license number |
| `employee_number` | VARCHAR(80) |  | Yes | Employee number |
| `phone` | VARCHAR(30) |  | Yes | Contact number |
| `assigned_jeepney_id` | BIGINT | FK → jeepneys | Yes | Assigned vehicle |
| `assigned_route_id` | BIGINT | FK → routes | Yes | Assigned route |
| `is_verified` | BOOLEAN |  | No | Verification status |
| `status` | ENUM |  | No | active or inactive |
| `created_at` | DATETIME |  | No | Creation timestamp |
| `updated_at` | DATETIME |  | No | Last update timestamp |

## 4. Admins

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `admin_id` | BIGINT | PK | No | Administrator identifier |
| `user_id` | BIGINT | FK → users, UNIQUE | No | Linked user account |
| `permissions` | JSON |  | Yes | Administrator permissions |
| `notes` | TEXT |  | Yes | Additional notes |
| `created_at` | DATETIME |  | No | Creation timestamp |
| `updated_at` | DATETIME |  | No | Last update timestamp |

## 5. Jeepneys

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `jeepney_id` | BIGINT | PK | No | Vehicle identifier |
| `plate_number` | VARCHAR(30) | UNIQUE | No | Vehicle plate number |
| `capacity` | INT |  | Yes | Passenger capacity |
| `vehicle_tag` | VARCHAR(80) |  | Yes | Internal vehicle tag |
| `jeepney_name` | VARCHAR(100) |  | Yes | Vehicle name |
| `manufacturer` | VARCHAR(100) |  | Yes | Vehicle manufacturer |
| `capacity_band` | VARCHAR(30) |  | No | Capacity classification |
| `status` | ENUM |  | No | active, inactive, maintenance |
| `current_driver_id` | BIGINT | FK → drivers | Yes | Current driver |
| `latitude` | DECIMAL(10,7) |  | Yes | Last known latitude |
| `longitude` | DECIMAL(10,7) |  | Yes | Last known longitude |
| `last_seen_at` | DATETIME |  | Yes | Last location update |
| `created_at`, `updated_at` | DATETIME |  | No | Record timestamps |

## 6. Routes

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `route_id` | BIGINT | PK | No | Route identifier |
| `name` | VARCHAR(150) |  | No | Route name |
| `code` | VARCHAR(50) | UNIQUE | No | Route code |
| `direction` | ENUM |  | No | up, down, circular |
| `status` | ENUM |  | No | active or inactive |
| `description` | TEXT |  | Yes | Route description |
| `path` | JSON |  | Yes | GeoJSON route path |
| `navigation` | JSON |  | Yes | Navigation and traffic data |
| `base_amount` | DECIMAL(10,2) |  | No | Base fare |
| `base_distance_km` | DECIMAL(10,2) |  | No | Included distance |
| `additional_amount_per_km` | DECIMAL(10,2) |  | No | Extra fare per kilometer |
| `created_at`, `updated_at` | DATETIME |  | No | Record timestamps |

## 7. Route Stops

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `route_stop_id` | BIGINT | PK | No | Stop identifier |
| `route_id` | BIGINT | FK → routes | No | Parent route |
| `name` | VARCHAR(150) |  | No | Stop name |
| `code` | VARCHAR(50) |  | Yes | Stop code |
| `stop_order` | INT |  | No | Sequence along route |
| `fare` | DECIMAL(10,2) |  | No | Stop fare |
| `latitude`, `longitude` | DECIMAL(10,7) |  | Yes | Stop coordinates |

## 8. Trip Sessions

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `trip_session_id` | BIGINT | PK | No | Trip identifier |
| `jeepney_id` | BIGINT | FK → jeepneys | No | Vehicle used |
| `driver_id` | BIGINT | FK → drivers | Yes | Operating driver |
| `route_id` | BIGINT | FK → routes | No | Route followed |
| `status` | ENUM |  | No | scheduled, active, completed, cancelled |
| `started_at`, `ended_at` | DATETIME |  | Yes | Trip times |
| `accept_requests` | BOOLEAN |  | No | Accept pickup requests |
| `occupancy_count` | INT |  | No | Current passengers |
| `active` | BOOLEAN |  | No | Active trip flag |
| `notes` | TEXT |  | Yes | Trip notes |

## 9. Pickup Requests

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `pickup_request_id` | BIGINT | PK | No | Request identifier |
| `passenger_id` | BIGINT | FK → passengers | No | Requesting passenger |
| `trip_session_id` | BIGINT | FK → trip_sessions | No | Requested trip |
| `route_id` | BIGINT | FK → routes | No | Requested route |
| `stop_ref` | VARCHAR(50) |  | Yes | Pickup stop |
| `pickup_latitude`, `pickup_longitude` | DECIMAL(10,7) |  | Yes | Pickup coordinates |
| `destination_stop_ref` | VARCHAR(50) |  | Yes | Destination stop |
| `destination_latitude`, `destination_longitude` | DECIMAL(10,7) |  | Yes | Destination coordinates |
| `fare_amount` | DECIMAL(10,2) |  | Yes | Fare snapshot |
| `status` | ENUM |  | No | pending, acknowledged, completed, expired, cancelled |
| `acknowledged_by` | BIGINT | FK → drivers | Yes | Acknowledging driver |
| `acknowledged_at` | DATETIME |  | Yes | Acknowledgement time |
| `source_note` | TEXT |  | Yes | Passenger note |
| `expires_at` | DATETIME |  | No | Request expiration |
| `created_at`, `updated_at` | DATETIME |  | No | Record timestamps |

## 10. Ride Sessions

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `ride_session_id` | BIGINT | PK | No | Ride identifier |
| `passenger_id` | BIGINT | FK → passengers | No | Passenger |
| `trip_session_id` | BIGINT | FK → trip_sessions | No | Active trip |
| `pickup_request_id` | BIGINT | FK → pickup_requests | No | Original request |
| `destination_stop_ref` | VARCHAR(50) |  | Yes | Destination stop |
| `destination_latitude`, `destination_longitude` | DECIMAL(10,7) |  | Yes | Destination coordinates |
| `fare_amount` | DECIMAL(10,2) |  | Yes | Fare snapshot |
| `status` | ENUM |  | No | waiting, onboard, completed |
| `boarded_at`, `ended_at` | DATETIME |  | Yes | Ride times |
| `can_send_stop_alert` | BOOLEAN |  | No | Stop-alert permission |

## 11. Stop Alerts

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `stop_alert_id` | BIGINT | PK | No | Alert identifier |
| `passenger_id` | BIGINT | FK → passengers | No | Passenger sending alert |
| `trip_session_id` | BIGINT | FK → trip_sessions | No | Active trip |
| `ride_session_id` | BIGINT | FK → ride_sessions | No | Current ride |
| `route_id` | BIGINT | FK → routes | No | Route reference |
| `stop_ref` | VARCHAR(50) |  | Yes | Requested stop |
| `note` | TEXT |  | Yes | Passenger message |
| `status` | ENUM |  | No | sent, seen, acknowledged, dismissed |
| `acknowledged_by` | BIGINT | FK → drivers | Yes | Acknowledging driver |
| `acknowledged_at` | DATETIME |  | Yes | Acknowledgement time |
| `latitude`, `longitude` | DECIMAL(10,7) |  | Yes | Alert location |

## 12. Notifications

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `notification_id` | BIGINT | PK | No | Notification identifier |
| `user_id` | BIGINT | FK → users | No | Recipient |
| `type` | VARCHAR(50) |  | No | Notification type |
| `title` | VARCHAR(200) |  | No | Notification title |
| `body` | TEXT |  | No | Notification message |
| `payload` | JSON |  | Yes | Additional data |
| `is_read` | BOOLEAN |  | No | Read status |
| `read_at`, `expires_at` | DATETIME |  | Yes | Read and expiration times |

## 13. Activity Logs

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `activity_log_id` | BIGINT | PK | No | Log identifier |
| `actor_id` | BIGINT | FK → users | Yes | User who performed action |
| `actor_role` | VARCHAR(30) |  | Yes | Role during action |
| `action` | VARCHAR(100) |  | No | Action performed |
| `entity` | VARCHAR(100) |  | No | Affected table/entity |
| `entity_id` | VARCHAR(50) |  | Yes | Affected record ID |
| `details` | JSON |  | Yes | Event details |
| `ip`, `client` | VARCHAR(255) |  | Yes | Request information |
| `created_at` | DATETIME |  | No | Action timestamp |

## 14. Authentication Tables

| Table | Primary Key | Important Columns | Foreign Key |
|---|---|---|---|
| `refresh_tokens` | `refresh_token_id` | `token_hash`, `expires_at`, `revoked_at`, `replaced_by_hash` | `user_id` → `users` |
| `password_reset_tokens` | `password_reset_token_id` | `token_hash`, `expires_at`, `used_at` | `user_id` → `users` |
| `admin_login_challenges` | `challenge_id` | `phone`, `code_hash`, `attempts`, `max_attempts`, `expires_at`, `used_at` | `user_id` → `users` |

## 15. Report Metadata

| Column | Data Type | Key | Null | Description |
|---|---|---|---|---|
| `report_metadata_id` | BIGINT | PK | No | Report record identifier |
| `report_type` | VARCHAR(100) |  | No | Type of report |
| `period_start` | DATE |  | No | Report start date |
| `period_end` | DATE |  | No | Report end date |
| `generated_by` | BIGINT | FK → users | No | Administrator who generated it |
| `params` | JSON |  | No | Report parameters |
| `result_summary` | JSON |  | No | Report summary |
| `file_url` | VARCHAR(500) |  | Yes | Generated report file |
| `created_at`, `updated_at` | DATETIME |  | No | Record timestamps |

## Relationship Summary

| Parent Table | Child Table | Relationship |
|---|---|---|
| `users` | `passengers`, `drivers`, `admins` | One-to-one profile |
| `routes` | `route_stops` | One-to-many |
| `jeepneys`, `drivers`, `routes` | `trip_sessions` | One-to-many |
| `passengers`, `trip_sessions`, `routes` | `pickup_requests` | One-to-many |
| `passengers`, `trip_sessions`, `pickup_requests` | `ride_sessions` | One-to-many |
| `passengers`, `trip_sessions`, `ride_sessions`, `routes` | `stop_alerts` | One-to-many |
| `users` | `notifications`, `activity_logs`, authentication tables, `report_metadata` | One-to-many |
