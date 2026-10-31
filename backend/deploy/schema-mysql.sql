
    create table athlete (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        date_of_birth date not null,
        development_stage varchar(255) not null,
        first_name varchar(255) not null,
        gender varchar(255),
        guardian_email varchar(255),
        guardian_name varchar(255),
        guardian_phone varchar(255),
        is_active bit not null,
        last_name varchar(255) not null,
        primary key (id)
    ) engine=InnoDB;

    create table athlete_note (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        note_text longtext not null,
        athlete_id binary(16) not null,
        coach_id binary(16),
        session_id binary(16) not null,
        session_block_id binary(16),
        primary key (id)
    ) engine=InnoDB;

    create table attendance_record (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        absence_reason varchar(255),
        status varchar(255) not null,
        athlete_id binary(16) not null,
        session_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table club (
        id binary(16) not null,
        updated_at datetime(6) not null,
        created_at datetime(6) not null,
        join_code varchar(255) not null,
        name varchar(255) not null,
        primary key (id)
    ) engine=InnoDB;

    create table coach (
        id binary(16) not null,
        updated_at datetime(6) not null,
        apple_user_id varchar(255),
        color_hex varchar(255),
        created_at datetime(6),
        deleted_at datetime(6),
        email varchar(255),
        name varchar(255) not null,
        nccp_level varchar(255),
        role varchar(255),
        club_id binary(16),
        requested_club_id binary(16),
        primary key (id)
    ) engine=InnoDB;

    create table coach_session (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        end_time datetime(6),
        is_archived bit not null,
        mf_cue varchar(255),
        scheduled_date date not null,
        session_name varchar(255) not null,
        session_note longtext,
        start_time datetime(6),
        status varchar(255) not null,
        team_note varchar(255),
        weather_note varchar(255),
        coach_id binary(16),
        team_id binary(16),
        primary key (id)
    ) engine=InnoDB;

    create table development_note (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        date date not null,
        text longtext not null,
        athlete_id binary(16) not null,
        coach_id binary(16),
        primary key (id)
    ) engine=InnoDB;

    create table development_note_tags (
        development_note_id binary(16) not null,
        tag varchar(255)
    ) engine=InnoDB;

    create table fitness_test_result (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        notes longtext,
        result float(53) not null,
        test_date date not null,
        test_type varchar(255) not null,
        unit varchar(255) not null,
        athlete_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table height_record (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        date date not null,
        height_cm float(53) not null,
        athlete_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table ktc_assessment (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        catch_score integer not null,
        created_at datetime(6),
        date date not null,
        exit_score integer not null,
        notes longtext,
        propulsion_draw_score integer not null,
        setup_recovery_score integer not null,
        ktc_window varchar(255) not null,
        athlete_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table pending_apple_revocation (
        id binary(16) not null,
        updated_at datetime(6) not null,
        attempts integer not null,
        client_id varchar(255) not null,
        created_at datetime(6),
        token varchar(2048) not null,
        token_type_hint varchar(255) not null,
        primary key (id)
    ) engine=InnoDB;

    create table performance_record (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        recorded_time_ms integer,
        rep_number integer not null,
        status varchar(255) not null,
        athlete_id binary(16) not null,
        session_block_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table regatta_result (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        event_distance_metres integer not null,
        location varchar(255),
        notes longtext,
        placement integer,
        regatta_date date not null,
        regatta_name varchar(255) not null,
        result_time_ms integer not null,
        total_competitors integer,
        athlete_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table session_block (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        block_name varchar(255) not null,
        block_type varchar(255) not null,
        coach_note varchar(255),
        distance_km float(53),
        drill_name varchar(255),
        duration_seconds integer,
        repetition_count integer not null,
        requires_time_entry bit not null,
        rest_interval_seconds integer,
        set_count integer not null,
        sort_order integer not null,
        target_distance_metres float(53),
        training_zone varchar(255),
        session_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table session_block_prescribed_rep_durations (
        session_block_id binary(16) not null,
        duration_sec integer,
        rep_index integer not null,
        primary key (session_block_id, rep_index),
        check ((rep_index>=0))
    ) engine=InnoDB;

    create table team (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        is_archived bit not null,
        team_description varchar(255),
        team_name varchar(255) not null,
        primary key (id)
    ) engine=InnoDB;

    create table team_membership (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        joined_date date not null,
        left_date date,
        athlete_id binary(16) not null,
        team_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table technical_assessment (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        created_at datetime(6),
        date date not null,
        overall_notes longtext,
        stage varchar(255) not null,
        athlete_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    create table technical_rating (
        id binary(16) not null,
        updated_at datetime(6) not null,
        club_id binary(16) not null,
        category varchar(255) not null,
        comment varchar(255),
        factor varchar(255) not null,
        score integer not null,
        assessment_id binary(16) not null,
        primary key (id)
    ) engine=InnoDB;

    alter table attendance_record 
       add constraint uq_attendance_session_athlete unique (session_id, athlete_id);

    alter table club 
       add constraint UKnbpf6bycx4mmhx1x9a3owgwms unique (join_code);

    alter table coach 
       add constraint UKamd278g3xa600rrx8huaibs7a unique (apple_user_id);

    alter table performance_record 
       add constraint uq_performance_block_athlete_rep unique (session_block_id, athlete_id, rep_number);

    alter table athlete_note 
       add constraint FK1xxfqnv07nf6p4144yedn6uv8 
       foreign key (athlete_id) 
       references athlete (id);

    alter table athlete_note 
       add constraint FK7cxo9vts0r7oyoblv1lhkch58 
       foreign key (coach_id) 
       references coach (id);

    alter table athlete_note 
       add constraint FKis6x2ujmvddcjri278bpfn2wd 
       foreign key (session_id) 
       references coach_session (id);

    alter table athlete_note 
       add constraint FKi2q2dfnme1t0s1pv5vjiyxesr 
       foreign key (session_block_id) 
       references session_block (id);

    alter table attendance_record 
       add constraint FK5uof3ebv0xijek1u1p8muo73o 
       foreign key (athlete_id) 
       references athlete (id);

    alter table attendance_record 
       add constraint FK6wfsc6vusj9mcyqsj9xmqrxdv 
       foreign key (session_id) 
       references coach_session (id);

    alter table coach 
       add constraint FK18plg2evnkgx7qmkk9it6m63 
       foreign key (club_id) 
       references club (id);

    alter table coach 
       add constraint FKa2g0498vcemmk0q02erhjhjy6 
       foreign key (requested_club_id) 
       references club (id);

    alter table coach_session 
       add constraint FKig90xravo18cob6n6h3i035fw 
       foreign key (coach_id) 
       references coach (id);

    alter table coach_session 
       add constraint FKeeq3upijw3mugqhd2yp7bke9h 
       foreign key (team_id) 
       references team (id);

    alter table development_note 
       add constraint FKoga6ysfxkobp5hb6xbef1vssf 
       foreign key (athlete_id) 
       references athlete (id);

    alter table development_note 
       add constraint FKqa979mrbhp5y0tesaf0u3yncs 
       foreign key (coach_id) 
       references coach (id);

    alter table development_note_tags 
       add constraint FK3ksjknj0379gikkwjfyp9nx8m 
       foreign key (development_note_id) 
       references development_note (id);

    alter table fitness_test_result 
       add constraint FK7yxcwpjrvgx1f6x3f53i6gucc 
       foreign key (athlete_id) 
       references athlete (id);

    alter table height_record 
       add constraint FKsjmbgny00iiopfdb41v4ln39q 
       foreign key (athlete_id) 
       references athlete (id);

    alter table ktc_assessment 
       add constraint FK33hm1icpfqsjouoipyvf622mp 
       foreign key (athlete_id) 
       references athlete (id);

    alter table performance_record 
       add constraint FK6adw0ndcu4tcpe1tdjpw58h7j 
       foreign key (athlete_id) 
       references athlete (id);

    alter table performance_record 
       add constraint FKmuspmgpp1thnpiche6fg0sq7i 
       foreign key (session_block_id) 
       references session_block (id);

    alter table regatta_result 
       add constraint FKmbek1b64kkkgs1j9u0ad7u622 
       foreign key (athlete_id) 
       references athlete (id);

    alter table session_block 
       add constraint FK74bpnpqoopk7dil4w3s09qved 
       foreign key (session_id) 
       references coach_session (id);

    alter table session_block_prescribed_rep_durations 
       add constraint FKheh2m02ehx42aa0xntp1kb9gr 
       foreign key (session_block_id) 
       references session_block (id);

    alter table team_membership 
       add constraint FKiyhcoh8qw53e3vm2v5gbo6wgi 
       foreign key (athlete_id) 
       references athlete (id);

    alter table team_membership 
       add constraint FKrf92vmiawfvyhxcmigcg10opm 
       foreign key (team_id) 
       references team (id);

    alter table technical_assessment 
       add constraint FKe8xyjj4cnr1mnh4vxag7gieq7 
       foreign key (athlete_id) 
       references athlete (id);

    alter table technical_rating 
       add constraint FKnrr44doa2e7ndhk3dgsbinh0b 
       foreign key (assessment_id) 
       references technical_assessment (id);
