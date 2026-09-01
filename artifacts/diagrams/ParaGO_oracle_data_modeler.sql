-- ParaGO relational documentation model for Oracle SQL Developer Data Modeler.
-- Import with File > Import > DDL File. This does not replace MongoDB Atlas.
-- MongoDB ObjectIds are represented as VARCHAR2(24 CHAR). Embedded objects that
-- do not need independent relationships are represented as JSON CLOB columns.

CREATE TABLE users (
    user_id             VARCHAR2(24 CHAR) NOT NULL,
    email               VARCHAR2(254 CHAR) NOT NULL,
    password_hash       VARCHAR2(255 CHAR),
    full_name           VARCHAR2(160 CHAR) NOT NULL,
    phone               VARCHAR2(32 CHAR),
    role                VARCHAR2(16 CHAR) NOT NULL,
    auth_provider       VARCHAR2(16 CHAR) DEFAULT 'local' NOT NULL,
    provider_id         VARCHAR2(255 CHAR),
    status              VARCHAR2(16 CHAR) DEFAULT 'active' NOT NULL,
    is_verified         NUMBER(1) DEFAULT 0 NOT NULL,
    last_login_at       TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (user_id),
    CONSTRAINT uk_users_email UNIQUE (email),
    CONSTRAINT ck_users_role CHECK (role IN ('PASSENGER', 'DRIVER', 'ADMIN')),
    CONSTRAINT ck_users_provider CHECK (auth_provider IN ('local', 'google', 'facebook')),
    CONSTRAINT ck_users_status CHECK (status IN ('active', 'suspended', 'deactivated')),
    CONSTRAINT ck_users_verified CHECK (is_verified IN (0, 1))
);

CREATE TABLE routes (
    route_id                    VARCHAR2(24 CHAR) NOT NULL,
    name                        VARCHAR2(160 CHAR) NOT NULL,
    code                        VARCHAR2(64 CHAR) NOT NULL,
    direction                   VARCHAR2(16 CHAR) DEFAULT 'circular' NOT NULL,
    status                      VARCHAR2(16 CHAR) DEFAULT 'active' NOT NULL,
    description                 VARCHAR2(1000 CHAR),
    path_geojson                CLOB,
    terminal_enabled            NUMBER(1) DEFAULT 1 NOT NULL,
    terminal_name               VARCHAR2(160 CHAR),
    terminal_stop_ref           VARCHAR2(100 CHAR),
    terminal_location_geojson   CLOB,
    terminal_radius_meters      NUMBER(10,2) DEFAULT 75,
    navigation_json             CLOB,
    base_fare_amount            NUMBER(10,2) DEFAULT 17 NOT NULL,
    base_distance_km            NUMBER(10,2) DEFAULT 4 NOT NULL,
    additional_fare_per_km      NUMBER(10,2) DEFAULT 2 NOT NULL,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_routes PRIMARY KEY (route_id),
    CONSTRAINT uk_routes_code UNIQUE (code),
    CONSTRAINT ck_routes_direction CHECK (direction IN ('up', 'down', 'circular')),
    CONSTRAINT ck_routes_status CHECK (status IN ('active', 'inactive')),
    CONSTRAINT ck_routes_terminal CHECK (terminal_enabled IN (0, 1)),
    CONSTRAINT ck_routes_path_json CHECK (path_geojson IS JSON),
    CONSTRAINT ck_routes_terminal_json CHECK (terminal_location_geojson IS JSON),
    CONSTRAINT ck_routes_navigation_json CHECK (navigation_json IS JSON)
);

CREATE TABLE jeepneys (
    jeepney_id                  VARCHAR2(24 CHAR) NOT NULL,
    plate_number                VARCHAR2(32 CHAR) NOT NULL,
    capacity                    NUMBER(5) NOT NULL,
    vehicle_tag                 VARCHAR2(80 CHAR),
    jeepney_name                VARCHAR2(160 CHAR),
    manufacturer                VARCHAR2(160 CHAR),
    capacity_band               VARCHAR2(32 CHAR),
    status                      VARCHAR2(16 CHAR) DEFAULT 'active' NOT NULL,
    current_driver_id           VARCHAR2(24 CHAR),
    last_location_geojson       CLOB,
    latest_location_order_json  CLOB,
    last_seen_at                TIMESTAMP WITH TIME ZONE,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_jeepneys PRIMARY KEY (jeepney_id),
    CONSTRAINT uk_jeepneys_plate UNIQUE (plate_number),
    CONSTRAINT ck_jeepneys_capacity CHECK (capacity > 0),
    CONSTRAINT ck_jeepneys_status CHECK (status IN ('active', 'inactive', 'maintenance')),
    CONSTRAINT ck_jeepneys_location CHECK (last_location_geojson IS JSON),
    CONSTRAINT ck_jeepneys_order_json CHECK (latest_location_order_json IS JSON)
);

CREATE TABLE passengers (
    passenger_id                VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    phone                       VARCHAR2(32 CHAR),
    photo_url                   VARCHAR2(1000 CHAR),
    emergency_contact_json      CLOB,
    default_route_id            VARCHAR2(24 CHAR),
    last_location_geojson       CLOB,
    last_seen_at                TIMESTAMP WITH TIME ZONE,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_passengers PRIMARY KEY (passenger_id),
    CONSTRAINT uk_passengers_user UNIQUE (user_id),
    CONSTRAINT ck_pass_emergency_json CHECK (emergency_contact_json IS JSON),
    CONSTRAINT ck_pass_location_json CHECK (last_location_geojson IS JSON)
);

CREATE TABLE drivers (
    driver_id                   VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    license_number              VARCHAR2(80 CHAR),
    employee_number             VARCHAR2(80 CHAR),
    phone                       VARCHAR2(32 CHAR),
    assigned_jeepney_id         VARCHAR2(24 CHAR),
    assigned_route_id           VARCHAR2(24 CHAR),
    status                      VARCHAR2(16 CHAR) DEFAULT 'inactive' NOT NULL,
    operating_mode              VARCHAR2(24 CHAR) DEFAULT 'route' NOT NULL,
    terminal_queue_status       VARCHAR2(24 CHAR) DEFAULT 'off_queue' NOT NULL,
    terminal_checked_in_at      TIMESTAMP WITH TIME ZONE,
    terminal_queue_number       NUMBER(10),
    terminal_stop_ref           VARCHAR2(100 CHAR),
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_drivers PRIMARY KEY (driver_id),
    CONSTRAINT uk_drivers_user UNIQUE (user_id),
    CONSTRAINT ck_drivers_status CHECK (status IN ('active', 'inactive')),
    CONSTRAINT ck_drivers_mode CHECK (operating_mode IN ('route', 'terminal_queue')),
    CONSTRAINT ck_drivers_queue_status CHECK (terminal_queue_status IN ('off_queue', 'waiting', 'loading', 'skipped', 'departed')),
    CONSTRAINT ck_drivers_queue_number CHECK (terminal_queue_number IS NULL OR terminal_queue_number > 0)
);

CREATE TABLE driver_license_documents (
    document_id                 VARCHAR2(24 CHAR) NOT NULL,
    driver_id                   VARCHAR2(24 CHAR) NOT NULL,
    document_side               VARCHAR2(8 CHAR) NOT NULL,
    object_key                  VARCHAR2(1024 CHAR) NOT NULL,
    mime_type                   VARCHAR2(100 CHAR) NOT NULL,
    size_bytes                  NUMBER(12) NOT NULL,
    uploaded_at                 TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_driver_license_docs PRIMARY KEY (document_id),
    CONSTRAINT uk_driver_license_side UNIQUE (driver_id, document_side),
    CONSTRAINT ck_driver_license_side CHECK (document_side IN ('front', 'back')),
    CONSTRAINT ck_driver_license_size CHECK (size_bytes > 0)
);

CREATE TABLE admins (
    admin_id                    VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    permissions_json            CLOB,
    notes                       VARCHAR2(2000 CHAR),
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_admins PRIMARY KEY (admin_id),
    CONSTRAINT uk_admins_user UNIQUE (user_id),
    CONSTRAINT ck_admin_permissions CHECK (permissions_json IS JSON)
);

CREATE TABLE route_waypoints (
    waypoint_id                 VARCHAR2(24 CHAR) NOT NULL,
    route_id                    VARCHAR2(24 CHAR) NOT NULL,
    sequence_number             NUMBER(6) NOT NULL,
    name                        VARCHAR2(160 CHAR),
    location_geojson            CLOB NOT NULL,
    CONSTRAINT pk_route_waypoints PRIMARY KEY (waypoint_id),
    CONSTRAINT uk_route_waypoint_seq UNIQUE (route_id, sequence_number),
    CONSTRAINT ck_waypoint_location CHECK (location_geojson IS JSON)
);

CREATE TABLE route_stops (
    stop_id                     VARCHAR2(24 CHAR) NOT NULL,
    route_id                    VARCHAR2(24 CHAR) NOT NULL,
    stop_order                  NUMBER(6) NOT NULL,
    name                        VARCHAR2(160 CHAR) NOT NULL,
    code                        VARCHAR2(64 CHAR),
    fare                        NUMBER(10,2) DEFAULT 0 NOT NULL,
    location_geojson            CLOB,
    CONSTRAINT pk_route_stops PRIMARY KEY (stop_id),
    CONSTRAINT uk_route_stop_order UNIQUE (route_id, stop_order),
    CONSTRAINT ck_route_stop_fare CHECK (fare >= 0),
    CONSTRAINT ck_stop_location CHECK (location_geojson IS JSON)
);

CREATE TABLE trip_sessions (
    trip_session_id             VARCHAR2(24 CHAR) NOT NULL,
    jeepney_id                  VARCHAR2(24 CHAR) NOT NULL,
    driver_id                   VARCHAR2(24 CHAR),
    route_id                    VARCHAR2(24 CHAR) NOT NULL,
    route_path_snapshot_json    CLOB,
    status                      VARCHAR2(16 CHAR) DEFAULT 'scheduled' NOT NULL,
    started_at                  TIMESTAMP WITH TIME ZONE,
    ended_at                    TIMESTAMP WITH TIME ZONE,
    accept_requests             NUMBER(1) DEFAULT 1 NOT NULL,
    manual_occupancy_count      NUMBER(6) DEFAULT 0 NOT NULL,
    occupancy_count             NUMBER(6) DEFAULT 0 NOT NULL,
    is_active                   NUMBER(1) DEFAULT 0 NOT NULL,
    notes                       VARCHAR2(2000 CHAR),
    operating_mode              VARCHAR2(24 CHAR) DEFAULT 'route' NOT NULL,
    terminal_queue_status       VARCHAR2(24 CHAR) DEFAULT 'off_queue' NOT NULL,
    terminal_queue_number       NUMBER(10),
    terminal_checked_in_at      TIMESTAMP WITH TIME ZONE,
    terminal_stop_ref           VARCHAR2(100 CHAR),
    terminal_location_geojson   CLOB,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_trip_sessions PRIMARY KEY (trip_session_id),
    CONSTRAINT ck_trip_status CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled')),
    CONSTRAINT ck_trip_accept CHECK (accept_requests IN (0, 1)),
    CONSTRAINT ck_trip_active CHECK (is_active IN (0, 1)),
    CONSTRAINT ck_trip_occupancy CHECK (manual_occupancy_count >= 0 AND occupancy_count >= 0),
    CONSTRAINT ck_trip_path_json CHECK (route_path_snapshot_json IS JSON),
    CONSTRAINT ck_trip_terminal_json CHECK (terminal_location_geojson IS JSON)
);

CREATE TABLE pickup_requests (
    pickup_request_id           VARCHAR2(24 CHAR) NOT NULL,
    passenger_id                VARCHAR2(24 CHAR) NOT NULL,
    trip_session_id             VARCHAR2(24 CHAR) NOT NULL,
    route_id                    VARCHAR2(24 CHAR) NOT NULL,
    stop_ref                    VARCHAR2(100 CHAR),
    pickup_location_geojson     CLOB,
    destination_geojson         CLOB,
    pickup_type                 VARCHAR2(16 CHAR),
    terminal_location_geojson   CLOB,
    fare_snapshot_json          CLOB,
    status                      VARCHAR2(32 CHAR) NOT NULL,
    acknowledged_by_driver_id   VARCHAR2(24 CHAR),
    auto_boarding_json          CLOB,
    expires_at                  TIMESTAMP WITH TIME ZONE,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_pickup_requests PRIMARY KEY (pickup_request_id),
    CONSTRAINT ck_pickup_type CHECK (pickup_type IS NULL OR pickup_type IN ('roadside', 'terminal')),
    CONSTRAINT ck_pickup_location CHECK (pickup_location_geojson IS JSON),
    CONSTRAINT ck_pickup_destination CHECK (destination_geojson IS JSON),
    CONSTRAINT ck_pickup_terminal CHECK (terminal_location_geojson IS JSON),
    CONSTRAINT ck_pickup_fare_json CHECK (fare_snapshot_json IS JSON),
    CONSTRAINT ck_pickup_boarding_json CHECK (auto_boarding_json IS JSON)
);

CREATE TABLE ride_sessions (
    ride_session_id             VARCHAR2(24 CHAR) NOT NULL,
    passenger_id                VARCHAR2(24 CHAR) NOT NULL,
    trip_session_id             VARCHAR2(24 CHAR) NOT NULL,
    pickup_request_id           VARCHAR2(24 CHAR) NOT NULL,
    pickup_type                 VARCHAR2(16 CHAR),
    boarding_method             VARCHAR2(32 CHAR),
    boarding_location_geojson   CLOB,
    destination_geojson         CLOB,
    fare_snapshot_json          CLOB,
    status                      VARCHAR2(32 CHAR) NOT NULL,
    offboarding_method          VARCHAR2(32 CHAR),
    auto_offboarding_json       CLOB,
    boarded_at                  TIMESTAMP WITH TIME ZONE,
    ended_at                    TIMESTAMP WITH TIME ZONE,
    can_send_stop_alert         NUMBER(1) DEFAULT 0 NOT NULL,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ride_sessions PRIMARY KEY (ride_session_id),
    CONSTRAINT uk_rides_pickup UNIQUE (pickup_request_id),
    CONSTRAINT ck_rides_stop_alert CHECK (can_send_stop_alert IN (0, 1)),
    CONSTRAINT ck_rides_boarding_geo CHECK (boarding_location_geojson IS JSON),
    CONSTRAINT ck_rides_destination CHECK (destination_geojson IS JSON),
    CONSTRAINT ck_rides_fare_json CHECK (fare_snapshot_json IS JSON),
    CONSTRAINT ck_rides_offboard_json CHECK (auto_offboarding_json IS JSON)
);

CREATE TABLE stop_alerts (
    stop_alert_id               VARCHAR2(24 CHAR) NOT NULL,
    passenger_id                VARCHAR2(24 CHAR) NOT NULL,
    trip_session_id             VARCHAR2(24 CHAR) NOT NULL,
    ride_session_id             VARCHAR2(24 CHAR) NOT NULL,
    route_id                    VARCHAR2(24 CHAR) NOT NULL,
    stop_ref                    VARCHAR2(100 CHAR),
    note                        VARCHAR2(1000 CHAR),
    status                      VARCHAR2(20 CHAR) NOT NULL,
    acknowledged_by_driver_id   VARCHAR2(24 CHAR),
    location_geojson            CLOB,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_stop_alerts PRIMARY KEY (stop_alert_id),
    CONSTRAINT ck_stop_alert_status CHECK (status IN ('sent', 'seen', 'acknowledged', 'dismissed')),
    CONSTRAINT ck_stop_alert_location CHECK (location_geojson IS JSON)
);

CREATE TABLE notifications (
    notification_id             VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    notification_type           VARCHAR2(80 CHAR) NOT NULL,
    title                       VARCHAR2(200 CHAR) NOT NULL,
    body                        VARCHAR2(2000 CHAR) NOT NULL,
    payload_json                CLOB,
    read_at                     TIMESTAMP WITH TIME ZONE,
    is_read                     NUMBER(1) DEFAULT 0 NOT NULL,
    category                    VARCHAR2(80 CHAR),
    expires_at                  TIMESTAMP WITH TIME ZONE,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_notifications PRIMARY KEY (notification_id),
    CONSTRAINT ck_notifications_read CHECK (is_read IN (0, 1)),
    CONSTRAINT ck_notifications_json CHECK (payload_json IS JSON)
);

CREATE TABLE activity_logs (
    activity_log_id             VARCHAR2(24 CHAR) NOT NULL,
    actor_id                    VARCHAR2(24 CHAR),
    actor_role                  VARCHAR2(16 CHAR),
    action_name                 VARCHAR2(120 CHAR) NOT NULL,
    entity_name                 VARCHAR2(120 CHAR) NOT NULL,
    entity_id                   VARCHAR2(64 CHAR),
    details_json                CLOB,
    ip_address                  VARCHAR2(64 CHAR),
    client_name                 VARCHAR2(255 CHAR),
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_activity_logs PRIMARY KEY (activity_log_id),
    CONSTRAINT ck_activity_details CHECK (details_json IS JSON)
);

CREATE TABLE refresh_tokens (
    refresh_token_id            VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    token_hash                  VARCHAR2(255 CHAR) NOT NULL,
    expires_at                  TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at                  TIMESTAMP WITH TIME ZONE,
    replaced_by_hash            VARCHAR2(255 CHAR),
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_refresh_tokens PRIMARY KEY (refresh_token_id),
    CONSTRAINT uk_refresh_token_hash UNIQUE (token_hash)
);

CREATE TABLE password_reset_tokens (
    reset_token_id              VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    token_hash                  VARCHAR2(255 CHAR) NOT NULL,
    expires_at                  TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at                     TIMESTAMP WITH TIME ZONE,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_password_reset_tokens PRIMARY KEY (reset_token_id),
    CONSTRAINT uk_password_reset_hash UNIQUE (token_hash)
);

CREATE TABLE admin_login_challenges (
    challenge_id                VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    phone                       VARCHAR2(32 CHAR) NOT NULL,
    code_hash                   VARCHAR2(255 CHAR) NOT NULL,
    expires_at                  TIMESTAMP WITH TIME ZONE NOT NULL,
    attempts                    NUMBER(6) DEFAULT 0 NOT NULL,
    max_attempts                NUMBER(6) NOT NULL,
    used_at                     TIMESTAMP WITH TIME ZONE,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_admin_login_challenges PRIMARY KEY (challenge_id)
);

CREATE TABLE announcements (
    announcement_id             VARCHAR2(24 CHAR) NOT NULL,
    title                       VARCHAR2(160 CHAR) NOT NULL,
    body                        CLOB NOT NULL,
    category                    VARCHAR2(80 CHAR),
    severity                    VARCHAR2(32 CHAR),
    audiences_json              CLOB NOT NULL,
    status                      VARCHAR2(32 CHAR) NOT NULL,
    revision                    NUMBER(10) DEFAULT 1 NOT NULL,
    starts_at                   TIMESTAMP WITH TIME ZONE,
    expires_at                  TIMESTAMP WITH TIME ZONE,
    created_by_admin_id         VARCHAR2(24 CHAR),
    updated_by_admin_id         VARCHAR2(24 CHAR),
    archived_by_admin_id        VARCHAR2(24 CHAR),
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_announcements PRIMARY KEY (announcement_id),
    CONSTRAINT ck_announcements_audience CHECK (audiences_json IS JSON)
);

CREATE TABLE announcement_dismissals (
    dismissal_id                VARCHAR2(24 CHAR) NOT NULL,
    announcement_id             VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    revision                    NUMBER(10) NOT NULL,
    dismissed_at                TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_announcement_dismissals PRIMARY KEY (dismissal_id),
    CONSTRAINT uk_announcement_dismissal UNIQUE (announcement_id, user_id, revision)
);

CREATE TABLE support_threads (
    support_thread_id           VARCHAR2(24 CHAR) NOT NULL,
    user_id                     VARCHAR2(24 CHAR) NOT NULL,
    user_role                   VARCHAR2(16 CHAR) NOT NULL,
    assigned_admin_id           VARCHAR2(24 CHAR),
    subject                     VARCHAR2(255 CHAR),
    category                    VARCHAR2(80 CHAR),
    status                      VARCHAR2(32 CHAR) NOT NULL,
    trip_session_id             VARCHAR2(24 CHAR),
    pickup_request_id           VARCHAR2(24 CHAR),
    ride_session_id             VARCHAR2(24 CHAR),
    route_id                    VARCHAR2(24 CHAR),
    last_message_at             TIMESTAMP WITH TIME ZONE,
    unread_admin_count          NUMBER(10) DEFAULT 0 NOT NULL,
    unread_user_count           NUMBER(10) DEFAULT 0 NOT NULL,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_support_threads PRIMARY KEY (support_thread_id),
    CONSTRAINT ck_support_user_role CHECK (user_role IN ('PASSENGER', 'DRIVER'))
);

CREATE TABLE support_messages (
    support_message_id          VARCHAR2(24 CHAR) NOT NULL,
    support_thread_id           VARCHAR2(24 CHAR) NOT NULL,
    sender_id                   VARCHAR2(24 CHAR) NOT NULL,
    sender_role                 VARCHAR2(16 CHAR) NOT NULL,
    body                        VARCHAR2(4000 CHAR) NOT NULL,
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_support_messages PRIMARY KEY (support_message_id),
    CONSTRAINT ck_support_sender_role CHECK (sender_role IN ('PASSENGER', 'DRIVER', 'ADMIN'))
);

CREATE TABLE report_metadata (
    report_metadata_id          VARCHAR2(24 CHAR) NOT NULL,
    report_type                 VARCHAR2(100 CHAR) NOT NULL,
    period_start                TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end                  TIMESTAMP WITH TIME ZONE NOT NULL,
    generated_by_user_id        VARCHAR2(24 CHAR) NOT NULL,
    parameters_json             CLOB,
    result_summary_json         CLOB,
    file_url                    VARCHAR2(1000 CHAR),
    created_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at                  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_report_metadata PRIMARY KEY (report_metadata_id),
    CONSTRAINT ck_report_parameters CHECK (parameters_json IS JSON),
    CONSTRAINT ck_report_summary CHECK (result_summary_json IS JSON)
);

-- Relationships are added after all tables so Oracle Data Modeler can resolve
-- the circular current-driver/assigned-jeepney association cleanly.
ALTER TABLE passengers ADD CONSTRAINT fk_passengers_user FOREIGN KEY (user_id) REFERENCES users (user_id);
ALTER TABLE passengers ADD CONSTRAINT fk_passengers_route FOREIGN KEY (default_route_id) REFERENCES routes (route_id);
ALTER TABLE drivers ADD CONSTRAINT fk_drivers_user FOREIGN KEY (user_id) REFERENCES users (user_id);
ALTER TABLE drivers ADD CONSTRAINT fk_drivers_jeepney FOREIGN KEY (assigned_jeepney_id) REFERENCES jeepneys (jeepney_id);
ALTER TABLE drivers ADD CONSTRAINT fk_drivers_route FOREIGN KEY (assigned_route_id) REFERENCES routes (route_id);
ALTER TABLE jeepneys ADD CONSTRAINT fk_jeepneys_driver FOREIGN KEY (current_driver_id) REFERENCES drivers (driver_id);
ALTER TABLE driver_license_documents ADD CONSTRAINT fk_license_docs_driver FOREIGN KEY (driver_id) REFERENCES drivers (driver_id) ON DELETE CASCADE;
ALTER TABLE admins ADD CONSTRAINT fk_admins_user FOREIGN KEY (user_id) REFERENCES users (user_id);
ALTER TABLE route_waypoints ADD CONSTRAINT fk_waypoints_route FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE;
ALTER TABLE route_stops ADD CONSTRAINT fk_route_stops_route FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE;
ALTER TABLE trip_sessions ADD CONSTRAINT fk_trips_jeepney FOREIGN KEY (jeepney_id) REFERENCES jeepneys (jeepney_id);
ALTER TABLE trip_sessions ADD CONSTRAINT fk_trips_driver FOREIGN KEY (driver_id) REFERENCES drivers (driver_id);
ALTER TABLE trip_sessions ADD CONSTRAINT fk_trips_route FOREIGN KEY (route_id) REFERENCES routes (route_id);
ALTER TABLE pickup_requests ADD CONSTRAINT fk_pickups_passenger FOREIGN KEY (passenger_id) REFERENCES passengers (passenger_id);
ALTER TABLE pickup_requests ADD CONSTRAINT fk_pickups_trip FOREIGN KEY (trip_session_id) REFERENCES trip_sessions (trip_session_id);
ALTER TABLE pickup_requests ADD CONSTRAINT fk_pickups_route FOREIGN KEY (route_id) REFERENCES routes (route_id);
ALTER TABLE pickup_requests ADD CONSTRAINT fk_pickups_driver FOREIGN KEY (acknowledged_by_driver_id) REFERENCES drivers (driver_id);
ALTER TABLE ride_sessions ADD CONSTRAINT fk_rides_passenger FOREIGN KEY (passenger_id) REFERENCES passengers (passenger_id);
ALTER TABLE ride_sessions ADD CONSTRAINT fk_rides_trip FOREIGN KEY (trip_session_id) REFERENCES trip_sessions (trip_session_id);
ALTER TABLE ride_sessions ADD CONSTRAINT fk_rides_pickup FOREIGN KEY (pickup_request_id) REFERENCES pickup_requests (pickup_request_id);
ALTER TABLE stop_alerts ADD CONSTRAINT fk_alerts_passenger FOREIGN KEY (passenger_id) REFERENCES passengers (passenger_id);
ALTER TABLE stop_alerts ADD CONSTRAINT fk_alerts_trip FOREIGN KEY (trip_session_id) REFERENCES trip_sessions (trip_session_id);
ALTER TABLE stop_alerts ADD CONSTRAINT fk_alerts_ride FOREIGN KEY (ride_session_id) REFERENCES ride_sessions (ride_session_id);
ALTER TABLE stop_alerts ADD CONSTRAINT fk_alerts_route FOREIGN KEY (route_id) REFERENCES routes (route_id);
ALTER TABLE stop_alerts ADD CONSTRAINT fk_alerts_driver FOREIGN KEY (acknowledged_by_driver_id) REFERENCES drivers (driver_id);
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE;
ALTER TABLE activity_logs ADD CONSTRAINT fk_activity_actor FOREIGN KEY (actor_id) REFERENCES users (user_id);
ALTER TABLE refresh_tokens ADD CONSTRAINT fk_refresh_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE;
ALTER TABLE password_reset_tokens ADD CONSTRAINT fk_reset_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE;
ALTER TABLE admin_login_challenges ADD CONSTRAINT fk_challenge_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE;
ALTER TABLE announcements ADD CONSTRAINT fk_announce_created_by FOREIGN KEY (created_by_admin_id) REFERENCES users (user_id);
ALTER TABLE announcements ADD CONSTRAINT fk_announce_updated_by FOREIGN KEY (updated_by_admin_id) REFERENCES users (user_id);
ALTER TABLE announcements ADD CONSTRAINT fk_announce_archived_by FOREIGN KEY (archived_by_admin_id) REFERENCES users (user_id);
ALTER TABLE announcement_dismissals ADD CONSTRAINT fk_dismiss_announcement FOREIGN KEY (announcement_id) REFERENCES announcements (announcement_id) ON DELETE CASCADE;
ALTER TABLE announcement_dismissals ADD CONSTRAINT fk_dismiss_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE;
ALTER TABLE support_threads ADD CONSTRAINT fk_support_thread_user FOREIGN KEY (user_id) REFERENCES users (user_id);
ALTER TABLE support_threads ADD CONSTRAINT fk_support_thread_admin FOREIGN KEY (assigned_admin_id) REFERENCES users (user_id);
ALTER TABLE support_threads ADD CONSTRAINT fk_support_thread_trip FOREIGN KEY (trip_session_id) REFERENCES trip_sessions (trip_session_id);
ALTER TABLE support_threads ADD CONSTRAINT fk_support_thread_pickup FOREIGN KEY (pickup_request_id) REFERENCES pickup_requests (pickup_request_id);
ALTER TABLE support_threads ADD CONSTRAINT fk_support_thread_ride FOREIGN KEY (ride_session_id) REFERENCES ride_sessions (ride_session_id);
ALTER TABLE support_threads ADD CONSTRAINT fk_support_thread_route FOREIGN KEY (route_id) REFERENCES routes (route_id);
ALTER TABLE support_messages ADD CONSTRAINT fk_support_message_thread FOREIGN KEY (support_thread_id) REFERENCES support_threads (support_thread_id) ON DELETE CASCADE;
ALTER TABLE support_messages ADD CONSTRAINT fk_support_message_sender FOREIGN KEY (sender_id) REFERENCES users (user_id);
ALTER TABLE report_metadata ADD CONSTRAINT fk_reports_generated_by FOREIGN KEY (generated_by_user_id) REFERENCES users (user_id);

CREATE INDEX ix_users_role_status ON users (role, status);
CREATE INDEX ix_drivers_route_status ON drivers (assigned_route_id, status);
CREATE INDEX ix_drivers_queue ON drivers (assigned_route_id, operating_mode, terminal_queue_status);
CREATE INDEX ix_jeepneys_status_driver ON jeepneys (status, current_driver_id);
CREATE INDEX ix_trips_status_started ON trip_sessions (status, started_at);
CREATE INDEX ix_trips_assignment ON trip_sessions (jeepney_id, driver_id, status);
CREATE INDEX ix_pickups_pass_status ON pickup_requests (passenger_id, status, created_at);
CREATE INDEX ix_pickups_trip_status ON pickup_requests (trip_session_id, status);
CREATE INDEX ix_alerts_trip_status ON stop_alerts (trip_session_id, status);
CREATE INDEX ix_notifications_user_read ON notifications (user_id, is_read, created_at);
CREATE INDEX ix_activity_actor_date ON activity_logs (actor_id, created_at);
CREATE INDEX ix_support_user_date ON support_threads (user_id, created_at);
CREATE INDEX ix_support_status_date ON support_threads (status, last_message_at);
CREATE INDEX ix_messages_thread_date ON support_messages (support_thread_id, created_at);
CREATE INDEX ix_reports_type_period ON report_metadata (report_type, period_start, period_end);

COMMENT ON TABLE driver_license_documents IS 'Private S3 document metadata; signed URLs are never persisted.';
COMMENT ON COLUMN driver_license_documents.object_key IS 'Private S3 object key, never a public URL.';
COMMENT ON TABLE route_waypoints IS 'Relational representation of the MongoDB routes.waypoints embedded array.';
COMMENT ON TABLE route_stops IS 'Relational representation of the MongoDB routes.stops embedded array.';
