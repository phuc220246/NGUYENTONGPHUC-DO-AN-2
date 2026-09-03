IF DB_ID(N'TOEIC_PracticeDB') IS NULL
BEGIN
    CREATE DATABASE TOEIC_PracticeDB;
END
GO

USE TOEIC_PracticeDB;
GO

------------------------------------------------------------
-- NHÓM BẢNG TÀI KHOẢN - PHÂN QUYỀN
------------------------------------------------------------

-- 1) BẢNG Account: lưu tài khoản đăng nhập
-- Không lưu mật khẩu dạng text, chỉ lưu HASH + SALT để bảo mật
CREATE TABLE dbo.Account (
    AccountId       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Username        NVARCHAR(50) NOT NULL,         -- Tên đăng nhập (không trùng)
    DisplayName     NVARCHAR(100) NULL,            -- Tên hiển thị (có thể trùng)

    PasswordHash    VARBINARY(64) NOT NULL,        -- Hash mật khẩu (PBKDF2/bcrypt...)
    PasswordSalt    VARBINARY(32) NOT NULL,        -- Salt ngẫu nhiên

    IsActive        BIT NOT NULL CONSTRAINT DF_Account_IsActive DEFAULT(1), -- 1=hoạt động,0=khóa
    CreatedAt       DATETIME2(0) NOT NULL CONSTRAINT DF_Account_CreatedAt DEFAULT(SYSDATETIME()),
    LastLoginAt     DATETIME2(0) NULL              -- Lần đăng nhập gần nhất
);
GO
-- Chống trùng Username
ALTER TABLE dbo.Account
ADD CONSTRAINT UQ_Account_Username UNIQUE (Username);
GO

-- 2) BẢNG Role: danh sách quyền (USER/ADMIN)
CREATE TABLE dbo.Role (
    RoleId      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RoleName    VARCHAR(30) NOT NULL                 -- USER, ADMIN...
);
GO

ALTER TABLE dbo.Role
ADD CONSTRAINT UQ_Role_RoleName UNIQUE (RoleName);
GO

-- 3) BẢNG AccountRole: bảng trung gian phân quyền (1 tài khoản có thể nhiều quyền)
CREATE TABLE dbo.AccountRole (
    AccountId   INT NOT NULL,
    RoleId      INT NOT NULL,
    CONSTRAINT PK_AccountRole PRIMARY KEY (AccountId, RoleId),
    CONSTRAINT FK_AccountRole_Account FOREIGN KEY (AccountId) REFERENCES dbo.Account(AccountId),
    CONSTRAINT FK_AccountRole_Role FOREIGN KEY (RoleId) REFERENCES dbo.Role(RoleId)
);
GO

------------------------------------------------------------
--  NHÓM BẢNG NGÂN HÀNG ĐỀ TOEIC
-- ETS (theo năm) -> TEST -> PART -> GROUP -> QUESTION -> ANSWER
------------------------------------------------------------

-- 4) BẢNG Part: 7 part cố định
-- Section: 1=Listening (Part 1-4), 2=Reading (Part 5-7)
CREATE TABLE dbo.Part (
    PartId      INT NOT NULL PRIMARY KEY,         -- 1..7
    PartName    VARCHAR(20) NOT NULL,             -- 'Part 1'..'Part 7'
    HasAudio    BIT NOT NULL,                     -- part có audio?
    HasImage    BIT NOT NULL,                     -- part có hình?
    Section     TINYINT NOT NULL                  -- 1=Listening, 2=Reading
        CONSTRAINT CK_Part_Section CHECK (Section IN (1,2))
);
GO

-- 5) BẢNG EtsSet: bộ ETS theo năm (vd: ETS 2023)
CREATE TABLE dbo.EtsSet (
    EtsId   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [Year]  INT NOT NULL,
    Title   NVARCHAR(100) NULL
);
GO

-- Chống trùng bộ ETS theo năm (tùy chọn)
ALTER TABLE dbo.EtsSet
ADD CONSTRAINT UQ_EtsSet_Year UNIQUE ([Year]);
GO

-- 6) BẢNG Test: mỗi ETS có nhiều test (thường 10)
CREATE TABLE dbo.Test (
    TestId  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EtsId   INT NOT NULL,
    TestNo  TINYINT NOT NULL,                 -- 1..10
    Title   NVARCHAR(100) NULL,

    CONSTRAINT FK_Test_EtsSet FOREIGN KEY (EtsId) REFERENCES dbo.EtsSet(EtsId)
        ON DELETE CASCADE
);
GO

-- Chống trùng TestNo trong cùng 1 ETS
ALTER TABLE dbo.Test
ADD CONSTRAINT UQ_Test_EtsId_TestNo UNIQUE (EtsId, TestNo);
GO

-- 7) BẢNG QuestionGroup: nhóm ngữ cảnh chung (audio/hình/passage) chứa nhiều câu hỏi
-- Ví dụ:
-- - Part 3/4: 1 đoạn hội thoại audio -> nhiều câu
-- - Part 6/7: 1 bài đọc passage -> nhiều câu
-- - Part 1/2/5: có thể xem mỗi group chứa 1 câu (GroupType=SINGLE)
CREATE TABLE dbo.QuestionGroup (
    GroupId     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TestId      INT NOT NULL,
    PartId      INT NOT NULL,

    GroupType   VARCHAR(20) NOT NULL
        CONSTRAINT CK_QuestionGroup_GroupType CHECK (GroupType IN ('SINGLE','CONVERSATION','PASSAGE')),

    AudioPath   VARCHAR(255) NULL,        -- Lưu đường dẫn file audio (không lưu file)
    ImagePath   VARCHAR(255) NULL,        -- Lưu đường dẫn file hình
    PassageText NVARCHAR(MAX) NULL,       -- Nội dung đoạn đọc (Part 6/7)

    OrderNo     INT NOT NULL,             -- Thứ tự group trong part

    CONSTRAINT FK_QuestionGroup_Test FOREIGN KEY (TestId) REFERENCES dbo.Test(TestId)
        ON DELETE CASCADE,
    CONSTRAINT FK_QuestionGroup_Part FOREIGN KEY (PartId) REFERENCES dbo.Part(PartId)
);
GO
ALTER TABLE dbo.QuestionGroup
ADD CONSTRAINT UQ_QuestionGroup_Order UNIQUE (TestId, PartId, OrderNo);
GO
-- 8) BẢNG GroupPassage CHO PART 7( mở rộng trong tương lai)
CREATE TABLE dbo.GroupPassage (
    PassageId       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    GroupId         INT NOT NULL,
    PassageNo       INT NOT NULL,
    Title           NVARCHAR(300) NULL,
    PassageText     NVARCHAR(MAX) NOT NULL,

    CONSTRAINT FK_GroupPassage_QuestionGroup
        FOREIGN KEY (GroupId) REFERENCES dbo.QuestionGroup(GroupId)
        ON DELETE CASCADE,

    CONSTRAINT UQ_GroupPassage_Group_PassageNo UNIQUE (GroupId, PassageNo)
);
GO

CREATE INDEX IX_GroupPassage_Group_PassageNo
ON dbo.GroupPassage(GroupId, PassageNo);
GO

-- 9) BẢNG Question: câu hỏi trong group
CREATE TABLE dbo.Question (
    QuestionId      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    GroupId         INT NOT NULL,

    QuestionText    NVARCHAR(MAX) NULL,       -- Nội dung câu hỏi (có thể NULL cho Part 1)
    Explanation     NVARCHAR(MAX) NULL,       -- Giải thích đáp án (hiển thị khi review)

    OrderInGroup    INT NOT NULL,             -- Thứ tự câu trong group

    CONSTRAINT FK_Question_Group FOREIGN KEY (GroupId) REFERENCES dbo.QuestionGroup(GroupId)
        ON DELETE CASCADE
);
GO

ALTER TABLE dbo.Question
ADD CONSTRAINT UQ_Question_Group_Order UNIQUE (GroupId, OrderInGroup);
GO

-- 10) BẢNG Answer: nội dung đáp án và đáp án đúng
CREATE TABLE dbo.Answer (
    AnswerId     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    QuestionId   INT NOT NULL,
    AnswerText   NVARCHAR(MAX) NOT NULL,
    IsCorrect    BIT NOT NULL,                -- 1=đúng, 0=sai

    CONSTRAINT FK_Answer_Question FOREIGN KEY (QuestionId) REFERENCES dbo.Question(QuestionId)
        ON DELETE CASCADE
);
GO
ALTER TABLE dbo.Answer
ADD CONSTRAINT UQ_Answer_Question_Answer UNIQUE (QuestionId, AnswerId);
GO

-- 11) BẢNG QuestionOption: gán nhãn A/B/C/D cho đáp án (thiết lập mặc định)
-- Sau này có thể đổi DisplayOrder để thay đổi thứ tự hiển thị mặc định
CREATE TABLE dbo.QuestionOption (
    OptionId        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    QuestionId      INT NOT NULL,
    AnswerId        INT NOT NULL,

    OptionLabel     CHAR(1) NOT NULL
        CONSTRAINT CK_QuestionOption_Label CHECK (OptionLabel IN ('A','B','C','D')),
    DisplayOrder    TINYINT NOT NULL
        CONSTRAINT CK_QuestionOption_DisplayOrder CHECK (DisplayOrder BETWEEN 1 AND 4),

    CONSTRAINT FK_QuestionOption_Question FOREIGN KEY (QuestionId) REFERENCES dbo.Question(QuestionId)
        ON DELETE CASCADE,
    CONSTRAINT FK_QuestionOption_Answer FOREIGN KEY (AnswerId) REFERENCES dbo.Answer(AnswerId)
);
GO
ALTER TABLE dbo.QuestionOption
ADD CONSTRAINT FK_QuestionOption_Question_Answer
    FOREIGN KEY (QuestionId, AnswerId)
    REFERENCES dbo.Answer(QuestionId, AnswerId);
GO
-- Mỗi câu chỉ có 1 A, 1 B, 1 C, 1 D
ALTER TABLE dbo.QuestionOption
ADD CONSTRAINT UQ_QuestionOption_Question_Label UNIQUE (QuestionId, OptionLabel);
GO

-- Một đáp án chỉ được gán 1 lần trong 1 câu
ALTER TABLE dbo.QuestionOption
ADD CONSTRAINT UQ_QuestionOption_Question_Answer UNIQUE (QuestionId, AnswerId);
GO

------------------------------------------------------------
--  NHÓM BẢNG LỊCH SỬ LÀM BÀI (Attempt)
-- Không trộn câu hỏi, CHỈ trộn đáp án A/B/C/D theo từng lần làm
------------------------------------------------------------

-- 12) BẢNG Attempt: 1 lần làm bài (FULL hoặc PART)
-- Lưu thời gian + tổng hợp đúng/sai/bỏ qua để hiển thị giống Study4
CREATE TABLE dbo.Attempt (
    AttemptId        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AccountId        INT NOT NULL,
    TestId           INT NOT NULL,

    Status           TINYINT NOT NULL CONSTRAINT DF_Attempt_Status DEFAULT(0),
    -- 0 = đang làm, 1 = đã nộp

    TimeLimitMinutes INT NULL, -- NULL = không giới hạn (theo combo time limit trên UI)

    Score            INT NULL, -- điểm (bạn có thể tính theo số câu đúng hoặc quy đổi TOEIC)

    StartedAt        DATETIME2(0) NOT NULL CONSTRAINT DF_Attempt_StartedAt DEFAULT(SYSDATETIME()),
    FinishedAt       DATETIME2(0) NULL,
    DurationSeconds  INT NULL, -- khi nộp bài: DATEDIFF(second, StartedAt, FinishedAt)

    -- Tổng hợp để hiển thị UI "đúng/sai/bỏ qua" như bạn muốn
    TotalQuestions   INT NOT NULL CONSTRAINT DF_Attempt_TotalQuestions DEFAULT(0),
    CorrectCount     INT NOT NULL CONSTRAINT DF_Attempt_Correct DEFAULT(0),
    WrongCount       INT NOT NULL CONSTRAINT DF_Attempt_Wrong DEFAULT(0),
    SkippedCount     INT NOT NULL CONSTRAINT DF_Attempt_Skipped DEFAULT(0),

    CONSTRAINT FK_Attempt_Account FOREIGN KEY (AccountId) REFERENCES dbo.Account(AccountId),
    CONSTRAINT FK_Attempt_Test FOREIGN KEY (TestId) REFERENCES dbo.Test(TestId)
);
GO

-- 13) BẢNG AttemptSectionTime: lưu thời gian theo Listening/Reading để thống kê giống Study4
-- Nếu user làm FULL: có 2 dòng (Section=1 và Section=2)
-- Nếu user làm PART: có thể chỉ lưu 1 dòng tương ứng Section của Part
CREATE TABLE dbo.AttemptSectionTime (
    AttemptId       INT NOT NULL,
    Section         TINYINT NOT NULL
        CONSTRAINT CK_AttemptSectionTime_Section CHECK (Section IN (1,2)), -- 1 Listening, 2 Reading

    StartedAt       DATETIME2(0) NULL,
    FinishedAt      DATETIME2(0) NULL,
    DurationSeconds INT NULL,

    TotalQuestions  INT NOT NULL CONSTRAINT DF_AST_Total DEFAULT(0),
    CorrectCount    INT NOT NULL CONSTRAINT DF_AST_Correct DEFAULT(0),
    WrongCount      INT NOT NULL CONSTRAINT DF_AST_Wrong DEFAULT(0),
    SkippedCount    INT NOT NULL CONSTRAINT DF_AST_Skipped DEFAULT(0),

    CONSTRAINT PK_AttemptSectionTime PRIMARY KEY (AttemptId, Section),
    CONSTRAINT FK_AttemptSectionTime_Attempt FOREIGN KEY (AttemptId) REFERENCES dbo.Attempt(AttemptId)
        ON DELETE CASCADE
);
GO

-- 14) BẢNG AttemptQuestion: danh sách câu hỏi trong attempt (GIỮ NGUYÊN thứ tự đề, KHÔNG RANDOM)
CREATE TABLE dbo.AttemptQuestion (
    AttemptQuestionId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AttemptId         INT NOT NULL,
    QuestionId        INT NOT NULL,
    PartId            INT NOT NULL,
    OrderNo           INT NOT NULL,

    CONSTRAINT FK_AttemptQuestion_Attempt FOREIGN KEY (AttemptId) REFERENCES dbo.Attempt(AttemptId)
        ON DELETE CASCADE
);
GO
ALTER TABLE dbo.AttemptQuestion
ADD CONSTRAINT FK_AttemptQuestion_Question
    FOREIGN KEY (QuestionId) REFERENCES dbo.Question(QuestionId);
GO

ALTER TABLE dbo.AttemptQuestion
ADD CONSTRAINT FK_AttemptQuestion_Part
    FOREIGN KEY (PartId) REFERENCES dbo.Part(PartId);
GO

-- 15) BẢNG AttemptOption: snapshot trộn đáp án A/B/C/D theo từng lần làm
-- Ý nghĩa: cùng 1 câu hỏi, lần làm 1 có thể đảo đáp án khác lần làm 2
CREATE TABLE dbo.AttemptOption (
    AttemptQuestionId    INT NOT NULL,
    AnswerId             INT NOT NULL,
    OptionLabel          CHAR(1) NOT NULL
        CONSTRAINT CK_AttemptOption_Label CHECK (OptionLabel IN ('A','B','C','D')),
    DisplayOrder         TINYINT NOT NULL
        CONSTRAINT CK_AttemptOption_DisplayOrder CHECK (DisplayOrder BETWEEN 1 AND 4),

    CONSTRAINT PK_AttemptOption PRIMARY KEY (AttemptQuestionId, OptionLabel),
    CONSTRAINT FK_AttemptOption_AttemptQuestion FOREIGN KEY (AttemptQuestionId) REFERENCES dbo.AttemptQuestion(AttemptQuestionId)
        ON DELETE CASCADE,
    CONSTRAINT FK_AttemptOption_Answer FOREIGN KEY (AnswerId) REFERENCES dbo.Answer(AnswerId)
);
GO

ALTER TABLE dbo.AttemptOption
ADD CONSTRAINT UQ_AttemptOption_AttemptQuestion_Answer UNIQUE (AttemptQuestionId, AnswerId);
GO

-- 16)  BẢNG AttemptAnswer: câu trả lời của người dùng
-- Nếu ChosenAnswerId = NULL => BỎ QUA
CREATE TABLE dbo.AttemptAnswer (
    AttemptQuestionId    INT NOT NULL PRIMARY KEY,
    ChosenOptionLabel    CHAR(1) NULL
        CONSTRAINT CK_AttemptAnswer_Label CHECK (ChosenOptionLabel IS NULL OR ChosenOptionLabel IN ('A','B','C','D')),
    ChosenAnswerId       INT NULL,
    IsCorrect            BIT NOT NULL CONSTRAINT DF_AttemptAnswer_IsCorrect DEFAULT(0),
    AnsweredAt           DATETIME2(0) NULL,

    CONSTRAINT FK_AttemptAnswer_AttemptQuestion FOREIGN KEY (AttemptQuestionId) REFERENCES dbo.AttemptQuestion(AttemptQuestionId)
        ON DELETE CASCADE,
    CONSTRAINT FK_AttemptAnswer_Answer FOREIGN KEY (ChosenAnswerId) REFERENCES dbo.Answer(AnswerId)
);
GO
USE TOEIC_PracticeDB;
GO
ALTER TABLE dbo.AttemptAnswer DROP CONSTRAINT DF_AttemptAnswer_IsCorrect;
GO

ALTER TABLE dbo.AttemptAnswer
ALTER COLUMN IsCorrect BIT NULL;
GO
------------------------------------------------------------
--  INDEX - TỐI ƯU TỐC ĐỘ TRUY VẤN
------------------------------------------------------------
CREATE INDEX IX_QuestionGroup_Test_Part_Order ON dbo.QuestionGroup(TestId, PartId, OrderNo);
CREATE INDEX IX_Question_Group_Order ON dbo.Question(GroupId, OrderInGroup);
CREATE INDEX IX_Answer_Question ON dbo.Answer(QuestionId);
CREATE INDEX IX_QuestionOption_Question_DisplayOrder ON dbo.QuestionOption(QuestionId, DisplayOrder);

CREATE INDEX IX_Attempt_Account_StartedAt ON dbo.Attempt(AccountId, StartedAt DESC);
CREATE INDEX IX_AttemptQuestion_Attempt_Order ON dbo.AttemptQuestion(AttemptId, OrderNo);
GO
--- Bổ sung Thêm IsActive và UpdatedAt ---
-- EtsSet
ALTER TABLE dbo.EtsSet
ADD IsActive BIT NOT NULL CONSTRAINT DF_EtsSet_IsActive DEFAULT(1),
    UpdatedAt DATETIME2(0) NULL;
GO

-- Test
ALTER TABLE dbo.Test
ADD IsActive BIT NOT NULL CONSTRAINT DF_Test_IsActive DEFAULT(1),
    UpdatedAt DATETIME2(0) NULL;
GO

-- QuestionGroup
ALTER TABLE dbo.QuestionGroup
ADD IsActive BIT NOT NULL CONSTRAINT DF_QuestionGroup_IsActive DEFAULT(1),
    UpdatedAt DATETIME2(0) NULL;
GO

-- Question
ALTER TABLE dbo.Question
ADD IsActive BIT NOT NULL CONSTRAINT DF_Question_IsActive DEFAULT(1),
    UpdatedAt DATETIME2(0) NULL;
GO

-- Answer
ALTER TABLE dbo.Answer
ADD IsActive BIT NOT NULL CONSTRAINT DF_Answer_IsActive DEFAULT(1),
    UpdatedAt DATETIME2(0) NULL;
GO
------------------------------------------------------------
--  CÁC SP DÙNG CHO HỆ THỐNG
------------------------------------------------------------
USE TOEIC_PracticeDB;
GO
------------------------------------------------------------
-- 1) SP: Lấy danh sách 7 Part
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Part_List', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Part_List;
GO

CREATE PROCEDURE dbo.sp_Part_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        PartId,
        PartName,
        HasAudio,
        HasImage,
        Section
    FROM dbo.Part
    ORDER BY PartId;
END
GO

------------------------------------------------------------
-- 2) SP: Lấy danh sách ETS (theo năm)
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Ets_List', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Ets_List;
GO

CREATE PROCEDURE dbo.sp_Ets_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        EtsId,
        [Year],
        Title
    FROM dbo.EtsSet
    ORDER BY [Year] DESC;
END
GO

------------------------------------------------------------
-- 3) SP: Lấy danh sách Test theo ETS
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Test_ListByEts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Test_ListByEts;
GO

CREATE PROCEDURE dbo.sp_Test_ListByEts
    @EtsId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        TestId,
        EtsId,
        TestNo,
        Title
    FROM dbo.Test
    WHERE EtsId = @EtsId
    ORDER BY TestNo;
END
GO
-------------------------------------------------------------

/* =========================================================
   SP ĐĂNG NHẬP + TẠO TÀI KHOẢN MẪU
   ========================================================= */

------------------------------------------------------------
-- 4) Lấy account theo Username
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Account_GetByUsername', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_GetByUsername;
GO

CREATE PROCEDURE dbo.sp_Account_GetByUsername
    @Username NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        AccountId,
        Username,
        DisplayName,
        PasswordHash,
        PasswordSalt,
        IsActive,
        CreatedAt,
        LastLoginAt
    FROM dbo.Account
    WHERE Username = @Username;
END
GO

------------------------------------------------------------
-- 5) Lấy roles của account
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Account_GetRoles', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_GetRoles;
GO

CREATE PROCEDURE dbo.sp_Account_GetRoles
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.RoleName
    FROM dbo.AccountRole ar
    INNER JOIN dbo.Role r ON ar.RoleId = r.RoleId
    WHERE ar.AccountId = @AccountId;
END
GO

------------------------------------------------------------
-- 6) Update LastLoginAt
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Account_UpdateLastLogin', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_UpdateLastLogin;
GO

CREATE PROCEDURE dbo.sp_Account_UpdateLastLogin
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Account
    SET LastLoginAt = SYSDATETIME()
    WHERE AccountId = @AccountId;
END
GO

------------------------------------------------------------
-- 7) Tạo tài khoản (username unique đã có constraint) - trả AccountId
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Account_Create', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_Create;
GO

CREATE PROCEDURE dbo.sp_Account_Create
    @Username NVARCHAR(50),
    @DisplayName NVARCHAR(100),
    @PasswordHash VARBINARY(64),
    @PasswordSalt VARBINARY(32),
    @IsActive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Account(Username, DisplayName, PasswordHash, PasswordSalt, IsActive)
    VALUES (@Username, @DisplayName, @PasswordHash, @PasswordSalt, @IsActive);

    SELECT SCOPE_IDENTITY() AS AccountId;
END
GO

------------------------------------------------------------
-- 8) Gán Role cho account (nếu đã tồn tại thì bỏ qua)
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Account_AssignRole', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_AssignRole;
GO

CREATE PROCEDURE dbo.sp_Account_AssignRole
    @AccountId INT,
    @RoleName NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RoleId INT = (SELECT TOP 1 RoleId FROM dbo.Role WHERE RoleName = @RoleName);

    IF @RoleId IS NULL
    BEGIN
        -- Nếu role chưa có thì tạo luôn (tiện cho đồ án)
        INSERT INTO dbo.Role(RoleName) VALUES (@RoleName);
        SET @RoleId = SCOPE_IDENTITY();
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.AccountRole WHERE AccountId = @AccountId AND RoleId = @RoleId)
    BEGIN
        INSERT INTO dbo.AccountRole(AccountId, RoleId) VALUES (@AccountId, @RoleId);
    END
END
GO

------------------------------------------------------------
-- 9) SP: sp_Attempt_GenerateOptions
-- Trộn đáp án cho tất cả câu hỏi của 1 Attempt
-- Chỉ trộn đáp án, không trộn câu hỏi
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Attempt_GenerateOptions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_GenerateOptions;
GO

CREATE PROCEDURE dbo.sp_Attempt_GenerateOptions
    @AttemptId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Nếu attempt này đã có option rồi thì không sinh lại
    IF EXISTS
    (
        SELECT 1
        FROM dbo.AttemptOption ao
        INNER JOIN dbo.AttemptQuestion aq
            ON ao.AttemptQuestionId = aq.AttemptQuestionId
        WHERE aq.AttemptId = @AttemptId
    )
        RETURN;

    /* =========================================================
       1) PART 1-4: GIỮ NGUYÊN THEO QUESTIONOPTION
       ========================================================= */
    INSERT INTO dbo.AttemptOption
    (
        AttemptQuestionId,
        AnswerId,
        OptionLabel,
        DisplayOrder
    )
    SELECT
        aq.AttemptQuestionId,
        qo.AnswerId,
        qo.OptionLabel,
        qo.DisplayOrder
    FROM dbo.AttemptQuestion aq
    INNER JOIN dbo.QuestionOption qo
        ON aq.QuestionId = qo.QuestionId
    WHERE aq.AttemptId = @AttemptId
      AND aq.PartId IN (1,2,3,4);

    /* =========================================================
       2) PART 5-7: SHUFFLE TỪ ANSWER
       ========================================================= */
    ;WITH X AS
    (
        SELECT
            aq.AttemptQuestionId,
            a.AnswerId,
            ROW_NUMBER() OVER
            (
                PARTITION BY aq.AttemptQuestionId
                ORDER BY NEWID()
            ) AS rn
        FROM dbo.AttemptQuestion aq
        INNER JOIN dbo.Answer a
            ON a.QuestionId = aq.QuestionId
        WHERE aq.AttemptId = @AttemptId
          AND aq.PartId IN (5,6,7)
    )
    INSERT INTO dbo.AttemptOption
    (
        AttemptQuestionId,
        AnswerId,
        OptionLabel,
        DisplayOrder
    )
    SELECT
        AttemptQuestionId,
        AnswerId,
        CASE rn
            WHEN 1 THEN 'A'
            WHEN 2 THEN 'B'
            WHEN 3 THEN 'C'
            WHEN 4 THEN 'D'
        END,
        CAST(rn AS TINYINT)
    FROM X
    WHERE rn BETWEEN 1 AND 4;
END
GO

/* =========================================================
   10) SP: sp_Attempt_Start
   - Tạo lần làm bài (Attempt)
   - Sinh danh sách câu hỏi cho attempt (AttemptQuestion)
   ========================================================= */
USE TOEIC_PracticeDB;
GO
IF OBJECT_ID('dbo.sp_Attempt_Start', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_Start;
GO

CREATE PROCEDURE dbo.sp_Attempt_Start
    @AccountId INT,
    @TestId INT,
    @PartIdsCsv VARCHAR(50) = '5',
    @TimeLimitMinutes INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1) Tạo Attempt
    INSERT INTO dbo.Attempt(AccountId, TestId, TimeLimitMinutes, StartedAt)
    VALUES (@AccountId, @TestId, @TimeLimitMinutes, SYSDATETIME());

    DECLARE @AttemptId INT = SCOPE_IDENTITY();

    -- 2) Tách danh sách Part
    ;WITH Parts AS (
        SELECT TRY_CAST(value AS INT) AS PartId
        FROM string_split(@PartIdsCsv, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL
    )
    -- 3) Tạo AttemptQuestion
    INSERT INTO dbo.AttemptQuestion(AttemptId, QuestionId, PartId, OrderNo)
    SELECT
        @AttemptId,
        q.QuestionId,
        g.PartId,
        ROW_NUMBER() OVER (ORDER BY g.PartId, g.OrderNo, q.OrderInGroup) AS OrderNo
    FROM dbo.QuestionGroup g
    JOIN dbo.Question q ON q.GroupId = g.GroupId
    JOIN Parts p ON p.PartId = g.PartId
    WHERE g.TestId = @TestId;

    -- ✅ 4) Tự sinh đáp án A/B/C/D theo AttemptOption (để làm bài + review dùng)
    EXEC dbo.sp_Attempt_GenerateOptions @AttemptId = @AttemptId;

    SELECT @AttemptId AS AttemptId;
END
GO
/* =========================================================
   11) SP: sp_Attempt_GetQuestionList
   - Lấy danh sách câu hỏi của 1 attempt theo đúng thứ tự OrderNo
   - Trả cả PassageText/Audio/Image để GUI hiển thị theo Group
   - Trả Explanation để sau này xem lại đáp án
   
   IF OBJECT_ID('dbo.sp_Attempt_GetQuestionList', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_GetQuestionList;
GO

CREATE PROCEDURE dbo.sp_Attempt_GetQuestionList
    @AttemptId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        aq.AttemptQuestionId,
        aq.AttemptId,
        aq.QuestionId,
        aq.PartId,
        aq.OrderNo,

        q.QuestionText,
        q.Explanation,

        g.GroupId,
        g.GroupType,
        g.AudioPath,
        g.ImagePath,
        g.PassageText,

        qo.OptionLabel,
        qo.DisplayOrder,
        a.AnswerId,
        a.AnswerText,

        aa.ChosenOptionLabel
    FROM dbo.AttemptQuestion aq
    JOIN dbo.Question q ON q.QuestionId = aq.QuestionId
    JOIN dbo.QuestionGroup g ON g.GroupId = q.GroupId
    JOIN dbo.QuestionOption qo ON qo.QuestionId = q.QuestionId
    JOIN dbo.Answer a ON a.AnswerId = qo.AnswerId
    LEFT JOIN dbo.AttemptAnswer aa ON aa.AttemptQuestionId = aq.AttemptQuestionId
    WHERE aq.AttemptId = @AttemptId
    ORDER BY aq.OrderNo, qo.DisplayOrder;
END
GO
========================================================= */
/* =========================================================
   12) SP: sp_Attempt_GetOptions
   - Lấy đáp án A/B/C/D theo AttemptQuestionId
   
   CREATE OR ALTER PROCEDURE dbo.sp_Attempt_GetOptions
    @AttemptQuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @QuestionId INT;
    SELECT @QuestionId = QuestionId
    FROM dbo.AttemptQuestion
    WHERE AttemptQuestionId = @AttemptQuestionId;

    SELECT
        qo.OptionLabel,
        qo.DisplayOrder,
        a.AnswerId,
        a.AnswerText
    FROM dbo.QuestionOption qo
    JOIN dbo.Answer a ON a.AnswerId = qo.AnswerId
    WHERE qo.QuestionId = @QuestionId
    ORDER BY qo.DisplayOrder;
END
GO
========================================================= */
/* =========================================================
   13) SP: sp_Attempt_SaveAnswer
   - Lưu đáp án user đã chọn (theo AttemptQuestionId)
   ========================================================= */
   IF OBJECT_ID('dbo.sp_Attempt_SaveAnswer', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_SaveAnswer;
GO

CREATE PROCEDURE dbo.sp_Attempt_SaveAnswer
    @AttemptQuestionId INT,
    @ChosenOptionLabel CHAR(1)  -- 'A'/'B'/'C'/'D' hoặc NULL (bỏ qua)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate AttemptQuestionId
    IF NOT EXISTS (SELECT 1 FROM dbo.AttemptQuestion WHERE AttemptQuestionId = @AttemptQuestionId)
        THROW 50001, N'AttemptQuestionId không hợp lệ.', 1;

    -- Chuẩn hóa label
    SET @ChosenOptionLabel = UPPER(LTRIM(RTRIM(@ChosenOptionLabel)));

    DECLARE @ChosenAnswerId INT = NULL;

    -- ✅ Map theo AttemptOption (đáp án đã trộn theo attempt)
    IF @ChosenOptionLabel IS NOT NULL AND @ChosenOptionLabel IN ('A','B','C','D')
    BEGIN
        SELECT @ChosenAnswerId = ao.AnswerId
        FROM dbo.AttemptOption ao
        WHERE ao.AttemptQuestionId = @AttemptQuestionId
          AND ao.OptionLabel = @ChosenOptionLabel;
    END

    -- Nếu label không hợp lệ / không tìm thấy -> coi như bỏ qua
    IF @ChosenAnswerId IS NULL
    BEGIN
        MERGE dbo.AttemptAnswer AS T
        USING (SELECT @AttemptQuestionId AS AttemptQuestionId) AS S
        ON T.AttemptQuestionId = S.AttemptQuestionId
        WHEN MATCHED THEN
            UPDATE SET
                ChosenOptionLabel = NULL,
                ChosenAnswerId = NULL,
                IsCorrect = 0,
                AnsweredAt = SYSDATETIME()
        WHEN NOT MATCHED THEN
            INSERT (AttemptQuestionId, ChosenOptionLabel, ChosenAnswerId, IsCorrect, AnsweredAt)
            VALUES (@AttemptQuestionId, NULL, NULL, 0, SYSDATETIME());

        RETURN;
    END

    -- Tính đúng/sai theo Answer.IsCorrect
    DECLARE @IsCorrect BIT = 0;
    SELECT @IsCorrect = a.IsCorrect
    FROM dbo.Answer a
    WHERE a.AnswerId = @ChosenAnswerId;

    -- Lưu AttemptAnswer
    MERGE dbo.AttemptAnswer AS T
    USING (SELECT @AttemptQuestionId AS AttemptQuestionId) AS S
    ON T.AttemptQuestionId = S.AttemptQuestionId
    WHEN MATCHED THEN
        UPDATE SET
            ChosenOptionLabel = @ChosenOptionLabel,
            ChosenAnswerId = @ChosenAnswerId,
            IsCorrect = @IsCorrect,
            AnsweredAt = SYSDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (AttemptQuestionId, ChosenOptionLabel, ChosenAnswerId, IsCorrect, AnsweredAt)
        VALUES (@AttemptQuestionId, @ChosenOptionLabel, @ChosenAnswerId, @IsCorrect, SYSDATETIME());
END
GO

/* =========================================================
   14) SP: sp_Attempt_Submit (SP nộp bài)
   ========================================================= */
USE TOEIC_PracticeDB;
GO
IF OBJECT_ID('dbo.sp_Attempt_Submit', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_Submit;
GO

CREATE  PROCEDURE dbo.sp_Attempt_Submit
    @AttemptId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Attempt WHERE AttemptId = @AttemptId)
    BEGIN
        RAISERROR(N'Attempt không tồn tại.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Attempt
    SET FinishedAt = SYSDATETIME(),
        Status = 1
    WHERE AttemptId = @AttemptId;

    UPDATE dbo.Attempt
    SET DurationSeconds = DATEDIFF(SECOND, StartedAt, FinishedAt)
    WHERE AttemptId = @AttemptId;

    DECLARE @Total INT = (SELECT COUNT(*) FROM dbo.AttemptQuestion WHERE AttemptId = @AttemptId);

    DECLARE @Correct INT =
    (
        SELECT COUNT(*)
        FROM dbo.AttemptAnswer aa
        JOIN dbo.AttemptQuestion aq ON aa.AttemptQuestionId = aq.AttemptQuestionId
        WHERE aq.AttemptId = @AttemptId AND aa.IsCorrect = 1
    );

    DECLARE @Wrong INT =
    (
        SELECT COUNT(*)
        FROM dbo.AttemptAnswer aa
        JOIN dbo.AttemptQuestion aq ON aa.AttemptQuestionId = aq.AttemptQuestionId
        WHERE aq.AttemptId = @AttemptId
          AND aa.ChosenOptionLabel IS NOT NULL
          AND aa.IsCorrect = 0
    );

    DECLARE @Skipped INT = @Total - (@Correct + @Wrong);
    IF @Skipped < 0 SET @Skipped = 0;

    UPDATE dbo.Attempt
    SET TotalQuestions = @Total,
        CorrectCount = @Correct,
        WrongCount = @Wrong,
        SkippedCount = @Skipped
    WHERE AttemptId = @AttemptId;

    SELECT
        AttemptId, AccountId, TestId, Status,
        TimeLimitMinutes, Score,
        StartedAt, FinishedAt, DurationSeconds,
        TotalQuestions, CorrectCount, WrongCount, SkippedCount
    FROM dbo.Attempt
    WHERE AttemptId = @AttemptId;
END
GO

/* =========================================================
   15) SP: sp_Attempt_Review_GetQuestions 
   (SP lấy danh sách câu + đáp án user chọn + đáp án đúng + giải thích)
   ========================================================= */
IF OBJECT_ID('dbo.sp_Attempt_Review_GetQuestions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_Review_GetQuestions;
GO

CREATE PROCEDURE dbo.sp_Attempt_Review_GetQuestions
    @AttemptId INT,
    @PartId INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        aq.AttemptQuestionId,
        aq.AttemptId,
        aq.QuestionId,
        aq.PartId,
        aq.OrderNo,

        g.GroupId,
        g.GroupType,
        g.AudioPath,
        g.ImagePath,
        g.PassageText,
        g.OrderNo AS GroupOrderNo,

        q.OrderInGroup,
        q.QuestionText,
        q.Explanation,

        aa.ChosenOptionLabel,
        aa.ChosenAnswerId,
        aa.IsCorrect,

        CorrectOptionLabel = aoCorrect.OptionLabel,
        CorrectAnswerId    = aoCorrect.AnswerId

    FROM dbo.AttemptQuestion aq
    INNER JOIN dbo.Question q
        ON q.QuestionId = aq.QuestionId
    INNER JOIN dbo.QuestionGroup g
        ON g.GroupId = q.GroupId
    LEFT JOIN dbo.AttemptAnswer aa
        ON aa.AttemptQuestionId = aq.AttemptQuestionId

    OUTER APPLY
    (
        SELECT TOP 1
            ao.OptionLabel,
            ao.AnswerId
        FROM dbo.AttemptOption ao
        INNER JOIN dbo.Answer a
            ON a.AnswerId = ao.AnswerId
        WHERE ao.AttemptQuestionId = aq.AttemptQuestionId
          AND a.IsCorrect = 1
        ORDER BY ao.DisplayOrder
    ) aoCorrect

    WHERE aq.AttemptId = @AttemptId
      AND (@PartId = 0 OR aq.PartId = @PartId)

    ORDER BY
        aq.PartId,
        g.OrderNo,
        q.OrderInGroup,
        aq.OrderNo;
END
GO

/* =========================================================
   16) SP: sp_Attempt_Review_GetOptions
   (SP lấy 4 đáp án (A/B/C/D) theo AttemptQuestionId (đã trộn))
   ========================================================= */
IF OBJECT_ID('dbo.sp_Attempt_Review_GetOptions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_Review_GetOptions;
GO

CREATE PROCEDURE dbo.sp_Attempt_Review_GetOptions
    @AttemptQuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ao.AttemptQuestionId,
        ao.OptionLabel,
        ao.DisplayOrder,
        ao.AnswerId,
        a.AnswerText,
        a.IsCorrect,
        aa.ChosenOptionLabel
    FROM dbo.AttemptOption ao
    INNER JOIN dbo.Answer a
        ON a.AnswerId = ao.AnswerId
    LEFT JOIN dbo.AttemptAnswer aa
        ON aa.AttemptQuestionId = ao.AttemptQuestionId
    WHERE ao.AttemptQuestionId = @AttemptQuestionId
    ORDER BY ao.DisplayOrder;
END
GO
/* =========================================================
   17) SP: SP: sp_Attempt_GetQuestionListWithOptions (lấy câu + options theo attempt)
   ========================================================= */
IF OBJECT_ID('dbo.sp_Attempt_GetQuestionListWithOptions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_GetQuestionListWithOptions;
GO

CREATE PROCEDURE dbo.sp_Attempt_GetQuestionListWithOptions
    @AttemptId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        aq.AttemptQuestionId,
        aq.AttemptId,
        aq.QuestionId,
        aq.PartId,
        aq.OrderNo,

        q.QuestionText,
        q.Explanation,

        g.GroupId,
        g.GroupType,
        g.AudioPath,
        g.ImagePath,
        g.PassageText,
        g.OrderNo AS GroupOrderNo,

        ao.OptionLabel,
        ao.DisplayOrder,
        ao.AnswerId,
        a.AnswerText,
        a.IsCorrect,

        aa.ChosenOptionLabel

    FROM dbo.AttemptQuestion aq
    INNER JOIN dbo.Question q ON q.QuestionId = aq.QuestionId
    INNER JOIN dbo.QuestionGroup g ON g.GroupId = q.GroupId

    -- ✅ options theo attempt (đã trộn)
    INNER JOIN dbo.AttemptOption ao ON ao.AttemptQuestionId = aq.AttemptQuestionId
    INNER JOIN dbo.Answer a ON a.AnswerId = ao.AnswerId

    -- ✅ đáp án user đã chọn (nếu có)
    LEFT JOIN dbo.AttemptAnswer aa ON aa.AttemptQuestionId = aq.AttemptQuestionId

    WHERE aq.AttemptId = @AttemptId
    ORDER BY aq.OrderNo, ao.DisplayOrder;
END
GO
------------------------

------------------------------------------------------------------------------
/* =========================================================
   18) SP: dbo.sp_Attempt_Review_GetQuestions_P6
   (SP lấy danh sách câu Part 6 + passage (group))
   ========================================================= */
IF OBJECT_ID('dbo.sp_Attempt_Review_GetQuestions_P6', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_Review_GetQuestions_P6;
GO

CREATE PROCEDURE dbo.sp_Attempt_Review_GetQuestions_P6
    @AttemptId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Correct AS (
        SELECT 
            q.QuestionId,
            qo.OptionLabel AS CorrectOptionLabel
        FROM dbo.Question q
        JOIN dbo.QuestionOption qo ON qo.QuestionId = q.QuestionId
        JOIN dbo.Answer a ON a.AnswerId = qo.AnswerId AND a.IsCorrect = 1
    )
    SELECT
        aq.AttemptQuestionId,
        aq.AttemptId,
        aq.PartId,
        aq.OrderNo,

        q.QuestionText,
        q.Explanation,

        aa.ChosenOptionLabel,
        c.CorrectOptionLabel,

        g.GroupId,
        g.OrderNo AS GroupOrderNo,
        g.PassageText
    FROM dbo.AttemptQuestion aq
    JOIN dbo.Question q ON q.QuestionId = aq.QuestionId
    JOIN dbo.QuestionGroup g ON g.GroupId = q.GroupId
    LEFT JOIN dbo.AttemptAnswer aa ON aa.AttemptQuestionId = aq.AttemptQuestionId
    LEFT JOIN Correct c ON c.QuestionId = q.QuestionId
    WHERE aq.AttemptId = @AttemptId
      AND aq.PartId = 6
    ORDER BY g.OrderNo, aq.OrderNo;
END
GO


/* =========================================================
   19) SP: sp_Attempt_GetAttemptParts
   ========================================================= */
IF OBJECT_ID('dbo.sp_Attempt_GetAttemptParts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_GetAttemptParts;
GO
CREATE PROCEDURE dbo.sp_Attempt_GetAttemptParts
    @AttemptId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT PartId
    FROM dbo.AttemptQuestion
    WHERE AttemptId = @AttemptId
    ORDER BY PartId;
END
GO

/* =========================================================
   20) SP: sp_Attempt_GetGroupPassages
   Lấy passage theo attempt 
   (Vì sp_Attempt_GetQuestionListWithOptions hiện trả mỗi option một dòng, nếu nhét thêm passage nhiều dòng vào đây thì bị lặp rất nhiều ==> NÊN TÁCH RIÊNG)
   ========================================================= */
IF OBJECT_ID('dbo.sp_Attempt_GetGroupPassages', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Attempt_GetGroupPassages;
GO

CREATE PROCEDURE dbo.sp_Attempt_GetGroupPassages
    @AttemptId INT,
    @PartId INT = 7
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH G AS
    (
        SELECT DISTINCT
            g.GroupId,
            g.OrderNo AS GroupOrderNo,
            g.PassageText AS FallbackPassageText
        FROM dbo.AttemptQuestion aq
        INNER JOIN dbo.Question q
            ON q.QuestionId = aq.QuestionId
        INNER JOIN dbo.QuestionGroup g
            ON g.GroupId = q.GroupId
        WHERE aq.AttemptId = @AttemptId
          AND aq.PartId = @PartId
    )
    -- Ưu tiên GroupPassage nếu có
    SELECT
        g.GroupId,
        g.GroupOrderNo,
        gp.PassageId,
        gp.PassageNo,
        gp.Title,
        gp.PassageText
    FROM G g
    INNER JOIN dbo.GroupPassage gp
        ON gp.GroupId = g.GroupId

    UNION ALL

    -- Fallback dữ liệu cũ: chưa seed GroupPassage
    SELECT
        g.GroupId,
        g.GroupOrderNo,
        CAST(NULL AS INT) AS PassageId,
        1 AS PassageNo,
        CAST(NULL AS NVARCHAR(300)) AS Title,
        g.FallbackPassageText AS PassageText
    FROM G g
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.GroupPassage gp
        WHERE gp.GroupId = g.GroupId
    )
      AND g.FallbackPassageText IS NOT NULL

    ORDER BY GroupOrderNo, PassageNo;
END
GO
/* =========================================================
   21) SP: sp_History_GetTestHeader
   lấy thông tin tiêu đề test để hiển thị đầu trang history
   ========================================================= */
USE TOEIC_PracticeDB;
GO
IF OBJECT_ID('dbo.sp_History_GetTestHeader', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_History_GetTestHeader;
GO

CREATE PROCEDURE dbo.sp_History_GetTestHeader
    @TestId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.TestId,
        e.[Year] AS EtsYear,
        t.TestNo,
        t.Title AS TestTitle,
        CAST(e.[Year] AS VARCHAR(10)) + ' - Test ' + CAST(t.TestNo AS VARCHAR(10)) AS TestDisplayTitle
    FROM dbo.Test t
    INNER JOIN dbo.EtsSet e
        ON t.EtsId = e.EtsId
    WHERE t.TestId = @TestId;
END
GO

/* =========================================================
   22) SP: sp_History_GetAttemptParts
   Lấy danh sách part đã làm trong một attempt
   ========================================================= */
   IF OBJECT_ID('dbo.sp_History_GetAttemptParts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_History_GetAttemptParts;
GO

CREATE PROCEDURE dbo.sp_History_GetAttemptParts
    @AttemptId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        aq.PartId,
        p.PartName
    FROM dbo.AttemptQuestion aq
    INNER JOIN dbo.Part p
        ON aq.PartId = p.PartId
    WHERE aq.AttemptId = @AttemptId
    ORDER BY aq.PartId;
END
GO

/* =========================================================
   23) SP: sp_History_GetAttemptsByAccountAndTest
   SP chính cho bảng history.
   ========================================================= */
IF OBJECT_ID('dbo.sp_History_GetAttemptsByAccountAndTest', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_History_GetAttemptsByAccountAndTest;
GO

CREATE PROCEDURE dbo.sp_History_GetAttemptsByAccountAndTest
    @AccountId INT,
    @TestId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH AttemptPartBase AS
    (
        SELECT
            a.AttemptId,
            aq.PartId
        FROM dbo.Attempt a
        INNER JOIN dbo.AttemptQuestion aq
            ON a.AttemptId = aq.AttemptId
        WHERE a.AccountId = @AccountId
          AND a.TestId = @TestId
          AND a.Status = 1
        GROUP BY
            a.AttemptId,
            aq.PartId
    ),
    AttemptPartCount AS
    (
        SELECT
            AttemptId,
            COUNT(*) AS PartCount,
            MIN(PartId) AS MinPartId,
            MAX(PartId) AS MaxPartId
        FROM AttemptPartBase
        GROUP BY AttemptId
    ),
    AttemptPartText AS
    (
        SELECT
            apc.AttemptId,
            CASE
                WHEN apc.PartCount = 7
                     AND apc.MinPartId = 1
                     AND apc.MaxPartId = 7
                    THEN 'Full test'
                WHEN apc.PartCount = 1
                    THEN 'Part ' + CAST(apc.MinPartId AS VARCHAR(10))
                ELSE
                    'Part ' +
                    STUFF
                    (
                        (
                            SELECT ',' + CAST(apb2.PartId AS VARCHAR(10))
                            FROM AttemptPartBase apb2
                            WHERE apb2.AttemptId = apc.AttemptId
                            ORDER BY apb2.PartId
                            FOR XML PATH(''), TYPE
                        ).value('.', 'NVARCHAR(MAX)'),
                        1,
                        1,
                        ''
                    )
            END AS PartDisplayText
        FROM AttemptPartCount apc
    )
    SELECT
        a.AttemptId,
        a.AccountId,
        a.TestId,
        a.StartedAt AS NgayLam,
        a.FinishedAt,
        a.DurationSeconds,
        a.TotalQuestions,
        a.CorrectCount,
        a.WrongCount,
        a.SkippedCount,
        CAST(a.CorrectCount AS VARCHAR(20)) + '/' + CAST(a.TotalQuestions AS VARCHAR(20)) AS ResultText,
        apt.PartDisplayText
    FROM dbo.Attempt a
    INNER JOIN AttemptPartText apt
        ON a.AttemptId = apt.AttemptId
    WHERE a.AccountId = @AccountId
      AND a.TestId = @TestId
      AND a.Status = 1
    ORDER BY a.StartedAt DESC, a.AttemptId DESC;
END
GO
/* =========================================================
   24) SP: sp_Stats_GetOverviewByAccount
   SP thống kê tổng quan toàn bộ tài khoản
   ========================================================= */
 USE TOEIC_PracticeDB;
GO
IF OBJECT_ID('dbo.sp_Stats_GetOverviewByAccount', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Stats_GetOverviewByAccount;
GO

CREATE PROCEDURE dbo.sp_Stats_GetOverviewByAccount
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        TotalSubmittedAttempts = COUNT(*),
        TotalQuestions         = ISNULL(SUM(a.TotalQuestions), 0),
        TotalCorrect           = ISNULL(SUM(a.CorrectCount), 0),
        TotalWrong             = ISNULL(SUM(a.WrongCount), 0),
        TotalSkipped           = ISNULL(SUM(a.SkippedCount), 0),
        AccuracyPercent        =
            CAST
            (
                CASE
                    WHEN ISNULL(SUM(a.TotalQuestions), 0) = 0 THEN 0
                    ELSE ISNULL(SUM(a.CorrectCount), 0) * 100.0 / SUM(a.TotalQuestions)
                END
                AS DECIMAL(5,2)
            ),
        AvgDurationSeconds     =
            CAST(AVG(CAST(a.DurationSeconds AS FLOAT)) AS INT),
        LastSubmittedAt        = MAX(a.FinishedAt)
    FROM dbo.Attempt a
    WHERE a.AccountId = @AccountId
      AND a.Status = 1;
END
GO
/* =========================================================
   25) SP: sp_Stats_GetByPart
   SP thống kê theo từng part
   ========================================================= */
   USE TOEIC_PracticeDB;
GO
   IF OBJECT_ID('dbo.sp_Stats_GetByPart', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Stats_GetByPart;
GO

CREATE PROCEDURE dbo.sp_Stats_GetByPart
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        aq.PartId,
        p.PartName,
        TotalQuestions =
            COUNT(*),
        CorrectCount =
            SUM(CASE WHEN aa.IsCorrect = 1 THEN 1 ELSE 0 END),
        WrongCount =
            SUM(CASE WHEN aa.ChosenAnswerId IS NOT NULL AND aa.IsCorrect = 0 THEN 1 ELSE 0 END),
        SkippedCount =
            SUM(CASE WHEN aa.AttemptQuestionId IS NULL OR aa.ChosenAnswerId IS NULL THEN 1 ELSE 0 END),
        AccuracyPercent =
            CAST
            (
                CASE
                    WHEN COUNT(*) = 0 THEN 0
                    ELSE SUM(CASE WHEN aa.IsCorrect = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
                END
                AS DECIMAL(5,2)
            )
    FROM dbo.Attempt a
    INNER JOIN dbo.AttemptQuestion aq
        ON a.AttemptId = aq.AttemptId
    INNER JOIN dbo.Part p
        ON aq.PartId = p.PartId
    LEFT JOIN dbo.AttemptAnswer aa
        ON aq.AttemptQuestionId = aa.AttemptQuestionId
    WHERE a.AccountId = @AccountId
      AND a.Status = 1
    GROUP BY
        aq.PartId,
        p.PartName
    ORDER BY
        aq.PartId;
END
GO
   /* =========================================================
   26) SP: sp_Stats_GetByTest
   SP thống kê theo từng test user đã làm
   ========================================================= */
   USE TOEIC_PracticeDB;
GO
   IF OBJECT_ID('dbo.sp_Stats_GetByTest', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Stats_GetByTest;
GO

CREATE PROCEDURE dbo.sp_Stats_GetByTest
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.TestId,
        e.[Year] AS EtsYear,
        t.TestNo,
        t.Title AS TestTitle,

        AttemptCount        = COUNT(*),
        TotalQuestions      = ISNULL(SUM(a.TotalQuestions), 0),
        TotalCorrect        = ISNULL(SUM(a.CorrectCount), 0),
        TotalWrong          = ISNULL(SUM(a.WrongCount), 0),
        TotalSkipped        = ISNULL(SUM(a.SkippedCount), 0),

        AvgAccuracyPercent  =
            CAST
            (
                AVG
                (
                    CASE
                        WHEN a.TotalQuestions = 0 THEN 0
                        ELSE a.CorrectCount * 100.0 / a.TotalQuestions
                    END
                )
                AS DECIMAL(5,2)
            ),

        BestAccuracyPercent =
            CAST
            (
                MAX
                (
                    CASE
                        WHEN a.TotalQuestions = 0 THEN 0
                        ELSE a.CorrectCount * 100.0 / a.TotalQuestions
                    END
                )
                AS DECIMAL(5,2)
            ),

        LastAttemptAt       = MAX(a.StartedAt)
    FROM dbo.Attempt a
    INNER JOIN dbo.Test t
        ON a.TestId = t.TestId
    INNER JOIN dbo.EtsSet e
        ON t.EtsId = e.EtsId
    WHERE a.AccountId = @AccountId
      AND a.Status = 1
    GROUP BY
        a.TestId,
        e.[Year],
        t.TestNo,
        t.Title
    ORDER BY
        e.[Year] DESC,
        t.TestNo ASC;
END
GO
   /* =========================================================
   27) SP: sp_Stats_GetRecentAttempts
   SP lấy các lần làm gần nhất để show dashboard/stat card/list
   ========================================================= */
   USE TOEIC_PracticeDB;
GO
   IF OBJECT_ID('dbo.sp_Stats_GetRecentAttempts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Stats_GetRecentAttempts;
GO

CREATE PROCEDURE dbo.sp_Stats_GetRecentAttempts
    @AccountId INT,
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH AttemptPartBase AS
    (
        SELECT
            a.AttemptId,
            aq.PartId
        FROM dbo.Attempt a
        INNER JOIN dbo.AttemptQuestion aq
            ON a.AttemptId = aq.AttemptId
        WHERE a.AccountId = @AccountId
          AND a.Status = 1
        GROUP BY
            a.AttemptId,
            aq.PartId
    ),
    AttemptPartCount AS
    (
        SELECT
            AttemptId,
            COUNT(*) AS PartCount,
            MIN(PartId) AS MinPartId,
            MAX(PartId) AS MaxPartId
        FROM AttemptPartBase
        GROUP BY AttemptId
    ),
    AttemptPartText AS
    (
        SELECT
            apc.AttemptId,
            CASE
                WHEN apc.PartCount = 7
                     AND apc.MinPartId = 1
                     AND apc.MaxPartId = 7
                    THEN 'Full test'
                WHEN apc.PartCount = 1
                    THEN 'Part ' + CAST(apc.MinPartId AS VARCHAR(10))
                ELSE
                    'Part ' +
                    STUFF
                    (
                        (
                            SELECT ',' + CAST(apb2.PartId AS VARCHAR(10))
                            FROM AttemptPartBase apb2
                            WHERE apb2.AttemptId = apc.AttemptId
                            ORDER BY apb2.PartId
                            FOR XML PATH(''), TYPE
                        ).value('.', 'NVARCHAR(MAX)'),
                        1,
                        1,
                        ''
                    )
            END AS PartDisplayText
        FROM AttemptPartCount apc
    )
    SELECT TOP (@TopN)
        a.AttemptId,
        a.TestId,
        e.[Year] AS EtsYear,
        t.TestNo,
        t.Title AS TestTitle,
        a.StartedAt,
        a.FinishedAt,
        a.DurationSeconds,
        a.TotalQuestions,
        a.CorrectCount,
        a.WrongCount,
        a.SkippedCount,
        ResultText =
            CAST(a.CorrectCount AS VARCHAR(20)) + '/' + CAST(a.TotalQuestions AS VARCHAR(20)),
        AccuracyPercent =
            CAST
            (
                CASE
                    WHEN a.TotalQuestions = 0 THEN 0
                    ELSE a.CorrectCount * 100.0 / a.TotalQuestions
                END
                AS DECIMAL(5,2)
            ),
        apt.PartDisplayText
    FROM dbo.Attempt a
    INNER JOIN dbo.Test t
        ON a.TestId = t.TestId
    INNER JOIN dbo.EtsSet e
        ON t.EtsId = e.EtsId
    INNER JOIN AttemptPartText apt
        ON a.AttemptId = apt.AttemptId
    WHERE a.AccountId = @AccountId
      AND a.Status = 1
    ORDER BY
        a.StartedAt DESC,
        a.AttemptId DESC;
END
GO
--- Các SP cho Admin CRUD ---
-- Admin CRUD cho EtsSet (28-32) --
/* =========================================================
   28) SP: sp_Admin_Ets_List
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Ets_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        EtsId,
        [Year],
        Title,
        IsActive,
        UpdatedAt
    FROM dbo.EtsSet
    ORDER BY [Year] DESC;
END
GO
/* =========================================================
   29) SP: sp_Admin_Ets_GetById
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Ets_GetById
    @EtsId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        EtsId,
        [Year],
        Title,
        IsActive,
        UpdatedAt
    FROM dbo.EtsSet
    WHERE EtsId = @EtsId;
END
GO
/* =========================================================
   30) SP: sp_Admin_Ets_Create
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Ets_Create
    @Year INT,
    @Title NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM dbo.EtsSet
        WHERE [Year] = @Year
    )
    BEGIN
        RAISERROR(N'Năm ETS đã tồn tại.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.EtsSet (
        [Year],
        Title,
        IsActive,
        UpdatedAt
    )
    VALUES (
        @Year,
        @Title,
        1,
        NULL
    );

    SELECT SCOPE_IDENTITY() AS NewEtsId;
END
GO
/* =========================================================
   31) SP: sp_Admin_Ets_Update
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Ets_Update
    @EtsId INT,
    @Year INT,
    @Title NVARCHAR(100) = NULL,
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.EtsSet
        WHERE EtsId = @EtsId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy EtsSet.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.EtsSet
        WHERE [Year] = @Year
          AND EtsId <> @EtsId
    )
    BEGIN
        RAISERROR(N'Năm ETS đã tồn tại.', 16, 1);
        RETURN;
    END

    UPDATE dbo.EtsSet
    SET
        [Year] = @Year,
        Title = @Title,
        IsActive = @IsActive,
        UpdatedAt = SYSDATETIME()
    WHERE EtsId = @EtsId;
END
GO
/* =========================================================
   32) SP: sp_Admin_Ets_Deactivate
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Ets_Deactivate
    @EtsId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.EtsSet
        WHERE EtsId = @EtsId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy EtsSet.', 16, 1);
        RETURN;
    END

    UPDATE dbo.EtsSet
    SET
        IsActive = 0,
        UpdatedAt = SYSDATETIME()
    WHERE EtsId = @EtsId;
END
GO
-- Admin CRUD cho Test (33-38) --
/* =========================================================
   33) SP: sp_Admin_Test_List
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Test_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.TestId,
        t.EtsId,
        e.[Year] AS EtsYear,
        t.TestNo,
        t.Title,
        t.IsActive,
        t.UpdatedAt
    FROM dbo.Test t
    INNER JOIN dbo.EtsSet e ON t.EtsId = e.EtsId
    ORDER BY e.[Year] DESC, t.TestNo ASC;
END
GO
/* =========================================================
   34) SP: sp_Admin_Test_ListByEts
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Test_ListByEts
    @EtsId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.TestId,
        t.EtsId,
        t.TestNo,
        t.Title,
        t.IsActive,
        t.UpdatedAt
    FROM dbo.Test t
    WHERE t.EtsId = @EtsId
    ORDER BY t.TestNo ASC;
END
GO
/* =========================================================
   35) SP: sp_Admin_Test_GetById
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Test_GetById
    @TestId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.TestId,
        t.EtsId,
        e.[Year] AS EtsYear,
        t.TestNo,
        t.Title,
        t.IsActive,
        t.UpdatedAt
    FROM dbo.Test t
    INNER JOIN dbo.EtsSet e ON t.EtsId = e.EtsId
    WHERE t.TestId = @TestId;
END
GO
/* =========================================================
   36) SP: sp_Admin_Test_Create
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Test_Create
    @EtsId INT,
    @TestNo TINYINT,
    @Title NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.EtsSet
        WHERE EtsId = @EtsId
    )
    BEGIN
        RAISERROR(N'EtsSet không tồn tại.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.Test
        WHERE EtsId = @EtsId
          AND TestNo = @TestNo
    )
    BEGIN
        RAISERROR(N'TestNo đã tồn tại trong bộ ETS này.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Test (
        EtsId,
        TestNo,
        Title,
        IsActive,
        UpdatedAt
    )
    VALUES (
        @EtsId,
        @TestNo,
        @Title,
        1,
        NULL
    );

    SELECT SCOPE_IDENTITY() AS NewTestId;
END
GO
/* =========================================================
   37) SP: sp_Admin_Test_Update
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Test_Update
    @TestId INT,
    @Title NVARCHAR(100) = NULL,
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Test
        WHERE TestId = @TestId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy Test.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Test
    SET
        Title = @Title,
        IsActive = @IsActive,
        UpdatedAt = SYSDATETIME()
    WHERE TestId = @TestId;
END
GO
/* =========================================================
   38) SP: sp_Admin_Test_Deactivate
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Test_Deactivate
    @TestId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Test
        WHERE TestId = @TestId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy Test.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Test
    SET
        IsActive = 0,
        UpdatedAt = SYSDATETIME()
    WHERE TestId = @TestId;
END
GO
-- Admin CRUD cho QuestionGroup (39-44) --
/* =========================================================
   39) SP: sp_Admin_Group_ListByTest
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Group_ListByTest
    @TestId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        g.GroupId,
        g.TestId,
        g.PartId,
        p.PartName,
        g.GroupType,
        g.AudioPath,
        g.ImagePath,
        g.PassageText,
        g.OrderNo,
        g.IsActive,
        g.UpdatedAt
    FROM dbo.QuestionGroup g
    INNER JOIN dbo.Part p ON g.PartId = p.PartId
    WHERE g.TestId = @TestId
    ORDER BY g.PartId ASC, g.OrderNo ASC;
END
GO
/* =========================================================
   40) SP: sp_Admin_Group_ListByTestPart
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Group_ListByTestPart
    @TestId INT,
    @PartId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        g.GroupId,
        g.TestId,
        g.PartId,
        p.PartName,
        g.GroupType,
        g.AudioPath,
        g.ImagePath,
        g.PassageText,
        g.OrderNo,
        g.IsActive,
        g.UpdatedAt
    FROM dbo.QuestionGroup g
    INNER JOIN dbo.Part p ON g.PartId = p.PartId
    WHERE g.TestId = @TestId
      AND g.PartId = @PartId
    ORDER BY g.OrderNo ASC;
END
GO
/* =========================================================
   41) SP: sp_Admin_Group_GetById
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Group_GetById
    @GroupId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        g.GroupId,
        g.TestId,
        t.TestNo,
        t.Title AS TestTitle,
        g.PartId,
        p.PartName,
        g.GroupType,
        g.AudioPath,
        g.ImagePath,
        g.PassageText,
        g.OrderNo,
        g.IsActive,
        g.UpdatedAt
    FROM dbo.QuestionGroup g
    INNER JOIN dbo.Test t ON g.TestId = t.TestId
    INNER JOIN dbo.Part p ON g.PartId = p.PartId
    WHERE g.GroupId = @GroupId;
END
GO
/* =========================================================
   42) SP: sp_Admin_Group_Create
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Group_Create
    @TestId INT,
    @PartId INT,
    @GroupType VARCHAR(20),
    @AudioPath VARCHAR(255) = NULL,
    @ImagePath VARCHAR(255) = NULL,
    @PassageText NVARCHAR(MAX) = NULL,
    @OrderNo INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Test
        WHERE TestId = @TestId
    )
    BEGIN
        RAISERROR(N'Test không tồn tại.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Part
        WHERE PartId = @PartId
    )
    BEGIN
        RAISERROR(N'Part không tồn tại.', 16, 1);
        RETURN;
    END

    IF @GroupType NOT IN ('SINGLE', 'CONVERSATION', 'PASSAGE')
    BEGIN
        RAISERROR(N'GroupType không hợp lệ.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.QuestionGroup
        WHERE TestId = @TestId
          AND PartId = @PartId
          AND OrderNo = @OrderNo
    )
    BEGIN
        RAISERROR(N'OrderNo đã tồn tại trong Test và Part này.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.QuestionGroup (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo,
        IsActive,
        UpdatedAt
    )
    VALUES (
        @TestId,
        @PartId,
        @GroupType,
        @AudioPath,
        @ImagePath,
        @PassageText,
        @OrderNo,
        1,
        NULL
    );

    SELECT SCOPE_IDENTITY() AS NewGroupId;
END
GO
/* =========================================================
   43) SP: sp_Admin_Group_Update
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Group_Update
    @GroupId INT,
    @GroupType VARCHAR(20),
    @AudioPath VARCHAR(255) = NULL,
    @ImagePath VARCHAR(255) = NULL,
    @PassageText NVARCHAR(MAX) = NULL,
    @OrderNo INT,
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TestId INT, @PartId INT;

    SELECT
        @TestId = TestId,
        @PartId = PartId
    FROM dbo.QuestionGroup
    WHERE GroupId = @GroupId;

    IF @TestId IS NULL OR @PartId IS NULL
    BEGIN
        RAISERROR(N'Không tìm thấy QuestionGroup.', 16, 1);
        RETURN;
    END

    IF @GroupType NOT IN ('SINGLE', 'CONVERSATION', 'PASSAGE')
    BEGIN
        RAISERROR(N'GroupType không hợp lệ.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.QuestionGroup
        WHERE TestId = @TestId
          AND PartId = @PartId
          AND OrderNo = @OrderNo
          AND GroupId <> @GroupId
    )
    BEGIN
        RAISERROR(N'OrderNo đã tồn tại trong Test và Part này.', 16, 1);
        RETURN;
    END

    UPDATE dbo.QuestionGroup
    SET
        GroupType = @GroupType,
        AudioPath = @AudioPath,
        ImagePath = @ImagePath,
        PassageText = @PassageText,
        OrderNo = @OrderNo,
        IsActive = @IsActive,
        UpdatedAt = SYSDATETIME()
    WHERE GroupId = @GroupId;
END
GO
/* =========================================================
   44) SP: sp_Admin_Group_Deactivate
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Group_Deactivate
    @GroupId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.QuestionGroup
        WHERE GroupId = @GroupId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy QuestionGroup.', 16, 1);
        RETURN;
    END

    UPDATE dbo.QuestionGroup
    SET
        IsActive = 0,
        UpdatedAt = SYSDATETIME()
    WHERE GroupId = @GroupId;
END
GO
-- Admin CRUD cho Question (45-49) --
/* =========================================================
   45) SP: sp_Admin_Question_ListByGroup
   ========================================================= */
IF OBJECT_ID('dbo.sp_Admin_Question_ListByGroup', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_Admin_Question_ListByGroup;
END
GO

-- 2. Tạo mới Stored Procedure
CREATE PROCEDURE dbo.sp_Admin_Question_ListByGroup
    @GroupId INT
AS
BEGIN
    -- Chặn các thông báo phụ để tối ưu hiệu suất
    SET NOCOUNT ON;

    SELECT
        q.QuestionId,
        q.GroupId,
        g.TestId,       -- Lấy từ bảng QuestionGroup
        g.PartId,       -- Lấy từ bảng QuestionGroup
        q.QuestionText,
        q.Explanation,
        q.OrderInGroup,
        q.IsActive,
        q.UpdatedAt
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE q.GroupId = @GroupId
    ORDER BY q.OrderInGroup ASC, q.QuestionId ASC;
END
GO
/* =========================================================
   46) SP: sp_Admin_Question_GetById
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Question_GetById
    @QuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        q.QuestionId,
        q.GroupId,
        g.TestId,
        g.PartId,
        q.QuestionText,
        q.Explanation,
        q.OrderInGroup,
        q.IsActive,
        q.UpdatedAt
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE q.QuestionId = @QuestionId;
END
GO
/* =========================================================
   47) SP: sp_Admin_Question_Create
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Question_Create
    @GroupId INT,
    @QuestionText NVARCHAR(MAX) = NULL,
    @Explanation NVARCHAR(MAX) = NULL,
    @OrderInGroup INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.QuestionGroup
        WHERE GroupId = @GroupId
    )
    BEGIN
        RAISERROR(N'QuestionGroup không tồn tại.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.Question
        WHERE GroupId = @GroupId
          AND OrderInGroup = @OrderInGroup
    )
    BEGIN
        RAISERROR(N'OrderInGroup đã tồn tại trong group này.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Question (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup,
        IsActive,
        UpdatedAt
    )
    VALUES (
        @GroupId,
        @QuestionText,
        @Explanation,
        @OrderInGroup,
        1,
        NULL
    );

    SELECT SCOPE_IDENTITY() AS NewQuestionId;
END
GO
/* =========================================================
   48) SP: sp_Admin_Question_Update
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Question_Update
    @QuestionId INT,
    @QuestionText NVARCHAR(MAX) = NULL,
    @Explanation NVARCHAR(MAX) = NULL,
    @OrderInGroup INT,
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @GroupId INT;

    SELECT @GroupId = GroupId
    FROM dbo.Question
    WHERE QuestionId = @QuestionId;

    IF @GroupId IS NULL
    BEGIN
        RAISERROR(N'Không tìm thấy Question.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.Question
        WHERE GroupId = @GroupId
          AND OrderInGroup = @OrderInGroup
          AND QuestionId <> @QuestionId
    )
    BEGIN
        RAISERROR(N'OrderInGroup đã tồn tại trong group này.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Question
    SET
        QuestionText = @QuestionText,
        Explanation = @Explanation,
        OrderInGroup = @OrderInGroup,
        IsActive = @IsActive,
        UpdatedAt = SYSDATETIME()
    WHERE QuestionId = @QuestionId;
END
GO
/* =========================================================
   49) SP: sp_Admin_Question_Deactivate
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Question_Deactivate
    @QuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Question
        WHERE QuestionId = @QuestionId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy Question.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Question
    SET
        IsActive = 0,
        UpdatedAt = SYSDATETIME()
    WHERE QuestionId = @QuestionId;
END
GO
-- Admin CRUD cho Answer (50-55) --
/* =========================================================
   50) SP: sp_Admin_Answer_ListByQuestion
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Answer_ListByQuestion
    @QuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.AnswerId,
        a.QuestionId,
        a.AnswerText,
        a.IsCorrect,
        a.IsActive,
        a.UpdatedAt
    FROM dbo.Answer a
    WHERE a.QuestionId = @QuestionId
    ORDER BY a.AnswerId ASC;
END
GO
/* =========================================================
   51) SP: sp_Admin_Answer_GetById
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Answer_GetById
    @AnswerId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.AnswerId,
        a.QuestionId,
        a.AnswerText,
        a.IsCorrect,
        a.IsActive,
        a.UpdatedAt
    FROM dbo.Answer a
    WHERE a.AnswerId = @AnswerId;
END
GO
/* =========================================================
   52) SP: sp_Admin_Answer_Create
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Answer_Create
    @QuestionId INT,
    @AnswerText NVARCHAR(MAX),
    @IsCorrect BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Question
        WHERE QuestionId = @QuestionId
    )
    BEGIN
        RAISERROR(N'Question không tồn tại.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Answer (
        QuestionId,
        AnswerText,
        IsCorrect,
        IsActive,
        UpdatedAt
    )
    VALUES (
        @QuestionId,
        @AnswerText,
        @IsCorrect,
        1,
        NULL
    );

    SELECT SCOPE_IDENTITY() AS NewAnswerId;
END
GO
/* =========================================================
   53) SP: sp_Admin_Answer_Update
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Answer_Update
    @AnswerId INT,
    @AnswerText NVARCHAR(MAX),
    @IsCorrect BIT,
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Answer
        WHERE AnswerId = @AnswerId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy Answer.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Answer
    SET
        AnswerText = @AnswerText,
        IsCorrect = @IsCorrect,
        IsActive = @IsActive,
        UpdatedAt = SYSDATETIME()
    WHERE AnswerId = @AnswerId;
END
GO
/* =========================================================
   54) SP: sp_Admin_Answer_Deactivate
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Answer_Deactivate
    @AnswerId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Answer
        WHERE AnswerId = @AnswerId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy Answer.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Answer
    SET
        IsActive = 0,
        UpdatedAt = SYSDATETIME()
    WHERE AnswerId = @AnswerId;
END
GO
/* =========================================================
   55) SP: sp_Admin_Answer_ValidateByQuestion
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Answer_ValidateByQuestion
    @QuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PartId INT;
    DECLARE @ActiveAnswerCount INT;
    DECLARE @CorrectCount INT;

    SELECT @PartId = g.PartId
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE q.QuestionId = @QuestionId;

    IF @PartId IS NULL
    BEGIN
        RAISERROR(N'Question không tồn tại.', 16, 1);
        RETURN;
    END

    SELECT
        @ActiveAnswerCount = COUNT(*),
        @CorrectCount = SUM(CASE WHEN IsCorrect = 1 THEN 1 ELSE 0 END)
    FROM dbo.Answer
    WHERE QuestionId = @QuestionId
      AND IsActive = 1;

    SELECT
        @QuestionId AS QuestionId,
        @PartId AS PartId,
        @ActiveAnswerCount AS ActiveAnswerCount,
        @CorrectCount AS CorrectCount,
        CASE
            WHEN @PartId = 2 AND @ActiveAnswerCount <> 3 THEN 0
            WHEN @PartId <> 2 AND @ActiveAnswerCount <> 4 THEN 0
            WHEN @CorrectCount <> 1 THEN 0
            ELSE 1
        END AS IsValid;
END
GO
-- Admin CRUD cho QuestionOption (56-58) --
/* =========================================================
   56) SP: sp_Admin_QuestionOption_ListByQuestion
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_QuestionOption_ListByQuestion
    @QuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        qo.OptionId,
        qo.QuestionId,
        qo.AnswerId,
        qo.OptionLabel,
        qo.DisplayOrder,
        a.AnswerText,
        a.IsCorrect,
        a.IsActive AS AnswerIsActive
    FROM dbo.QuestionOption qo
    INNER JOIN dbo.Answer a ON qo.AnswerId = a.AnswerId
    WHERE qo.QuestionId = @QuestionId
    ORDER BY qo.DisplayOrder ASC, qo.OptionLabel ASC;
END
GO
/* =========================================================
   57) SP: sp_Admin_QuestionOption_SaveBatch
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_QuestionOption_SaveBatch
    @QuestionId INT,
    @AnswerId_A INT,
    @AnswerId_B INT,
    @AnswerId_C INT,
    @AnswerId_D INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PartId INT;

    SELECT @PartId = g.PartId
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE q.QuestionId = @QuestionId;

    IF @PartId IS NULL
    BEGIN
        RAISERROR(N'Question không tồn tại.', 16, 1);
        RETURN;
    END

    IF @AnswerId_A IS NULL OR @AnswerId_B IS NULL OR @AnswerId_C IS NULL
    BEGIN
        RAISERROR(N'Phải có đủ Answer cho A, B, C.', 16, 1);
        RETURN;
    END

    IF @PartId = 2 AND @AnswerId_D IS NOT NULL
    BEGIN
        RAISERROR(N'Part 2 chỉ được có 3 option A, B, C.', 16, 1);
        RETURN;
    END

    IF @PartId <> 2 AND @AnswerId_D IS NULL
    BEGIN
        RAISERROR(N'Part này phải có đủ 4 option A, B, C, D.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        WHERE @AnswerId_A = @AnswerId_B
           OR @AnswerId_A = @AnswerId_C
           OR @AnswerId_B = @AnswerId_C
           OR (@AnswerId_D IS NOT NULL AND @AnswerId_A = @AnswerId_D)
           OR (@AnswerId_D IS NOT NULL AND @AnswerId_B = @AnswerId_D)
           OR (@AnswerId_D IS NOT NULL AND @AnswerId_C = @AnswerId_D)
    )
    BEGIN
        RAISERROR(N'Các AnswerId không được trùng nhau.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.Answer WHERE AnswerId = @AnswerId_A AND QuestionId = @QuestionId)
    BEGIN
        RAISERROR(N'Answer A không thuộc Question này.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.Answer WHERE AnswerId = @AnswerId_B AND QuestionId = @QuestionId)
    BEGIN
        RAISERROR(N'Answer B không thuộc Question này.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.Answer WHERE AnswerId = @AnswerId_C AND QuestionId = @QuestionId)
    BEGIN
        RAISERROR(N'Answer C không thuộc Question này.', 16, 1);
        RETURN;
    END

    IF @AnswerId_D IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Answer WHERE AnswerId = @AnswerId_D AND QuestionId = @QuestionId)
    BEGIN
        RAISERROR(N'Answer D không thuộc Question này.', 16, 1);
        RETURN;
    END

    DELETE FROM dbo.QuestionOption
    WHERE QuestionId = @QuestionId;

    INSERT INTO dbo.QuestionOption (QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
        (@QuestionId, @AnswerId_A, 'A', 1),
        (@QuestionId, @AnswerId_B, 'B', 2),
        (@QuestionId, @AnswerId_C, 'C', 3);

    IF @AnswerId_D IS NOT NULL
    BEGIN
        INSERT INTO dbo.QuestionOption (QuestionId, AnswerId, OptionLabel, DisplayOrder)
        VALUES (@QuestionId, @AnswerId_D, 'D', 4);
    END
END
GO
/* =========================================================
   58) SP: sp_Admin_QuestionOption_ValidateByQuestion
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_QuestionOption_ValidateByQuestion
    @QuestionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PartId INT;
    DECLARE @OptionCount INT;

    SELECT @PartId = g.PartId
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE q.QuestionId = @QuestionId;

    IF @PartId IS NULL
    BEGIN
        RAISERROR(N'Question không tồn tại.', 16, 1);
        RETURN;
    END

    SELECT @OptionCount = COUNT(*)
    FROM dbo.QuestionOption
    WHERE QuestionId = @QuestionId;

    SELECT
        @QuestionId AS QuestionId,
        @PartId AS PartId,
        @OptionCount AS OptionCount,
        CASE
            WHEN @PartId = 2 AND @OptionCount = 3 THEN 1
            WHEN @PartId <> 2 AND @OptionCount = 4 THEN 1
            ELSE 0
        END AS IsValid;
END
GO
-- Admin CRUD cho Account (59-66) --
/* =========================================================
   59) SP: sp_Admin_Account_List
   - đổ danh sách tài khoản cho grid admin, lấy luôn role hiện tại
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Account_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.AccountId,
        a.Username,
        a.DisplayName,
        a.IsActive,
        a.CreatedAt,
        a.LastLoginAt,
        r.RoleName
    FROM dbo.Account a
    LEFT JOIN dbo.AccountRole ar ON a.AccountId = ar.AccountId
    LEFT JOIN dbo.Role r ON ar.RoleId = r.RoleId
    ORDER BY a.AccountId DESC;
END
GO
/* =========================================================
   60) SP: sp_Admin_Account_GetById
   - lấy chi tiết 1 tài khoản để đổ form sửa
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Account_GetById
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.AccountId,
        a.Username,
        a.DisplayName,
        a.IsActive,
        a.CreatedAt,
        a.LastLoginAt,
        r.RoleName
    FROM dbo.Account a
    LEFT JOIN dbo.AccountRole ar ON a.AccountId = ar.AccountId
    LEFT JOIN dbo.Role r ON ar.RoleId = r.RoleId
    WHERE a.AccountId = @AccountId;
END
GO
/* =========================================================
   61) SP: sp_Admin_Role_List
   - bind combobox role trong form admin
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Role_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        RoleId,
        RoleName
    FROM dbo.Role
    ORDER BY RoleName ASC;
END
GO
/* =========================================================
   62) SP: sp_Admin_Account_Create
   - Tạo tài khoản mới, gán 1 role
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Account_Create
    @Username      NVARCHAR(50),
    @DisplayName   NVARCHAR(100) = NULL,
    @PasswordHash  VARBINARY(64),
    @PasswordSalt  VARBINARY(32),
    @RoleName      VARCHAR(30),
    @IsActive      BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RoleId INT;
    DECLARE @NewAccountId INT;

    IF EXISTS (
        SELECT 1
        FROM dbo.Account
        WHERE Username = @Username
    )
    BEGIN
        RAISERROR(N'Username đã tồn tại.', 16, 1);
        RETURN;
    END

    SELECT @RoleId = RoleId
    FROM dbo.Role
    WHERE RoleName = @RoleName;

    IF @RoleId IS NULL
    BEGIN
        RAISERROR(N'Role không tồn tại.', 16, 1);
        RETURN;
    END

    BEGIN TRAN;

    INSERT INTO dbo.Account (
        Username,
        DisplayName,
        PasswordHash,
        PasswordSalt,
        IsActive,
        CreatedAt,
        LastLoginAt
    )
    VALUES (
        @Username,
        @DisplayName,
        @PasswordHash,
        @PasswordSalt,
        @IsActive,
        SYSDATETIME(),
        NULL
    );

    SET @NewAccountId = SCOPE_IDENTITY();

    INSERT INTO dbo.AccountRole (
        AccountId,
        RoleId
    )
    VALUES (
        @NewAccountId,
        @RoleId
    );

    COMMIT TRAN;

    SELECT @NewAccountId AS NewAccountId;
END
GO
/* =========================================================
   63) SP: sp_Admin_Account_Update
   - sửa thông tin tài khoản
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Account_Update
    @AccountId     INT,
    @DisplayName   NVARCHAR(100) = NULL,
    @RoleName      VARCHAR(30),
    @IsActive      BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RoleId INT;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Account
        WHERE AccountId = @AccountId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy tài khoản.', 16, 1);
        RETURN;
    END

    SELECT @RoleId = RoleId
    FROM dbo.Role
    WHERE RoleName = @RoleName;

    IF @RoleId IS NULL
    BEGIN
        RAISERROR(N'Role không tồn tại.', 16, 1);
        RETURN;
    END

    BEGIN TRAN;

    UPDATE dbo.Account
    SET
        DisplayName = @DisplayName,
        IsActive = @IsActive
    WHERE AccountId = @AccountId;

    DELETE FROM dbo.AccountRole
    WHERE AccountId = @AccountId;

    INSERT INTO dbo.AccountRole (
        AccountId,
        RoleId
    )
    VALUES (
        @AccountId,
        @RoleId
    );

    COMMIT TRAN;
END
GO
/* =========================================================
   64) SP: sp_Admin_Account_SetActive
   - khóa / mở khóa nhanh tài khoản
   ========================================================= */
   CREATE OR ALTER PROCEDURE dbo.sp_Admin_Account_SetActive
    @AccountId INT,
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Account
        WHERE AccountId = @AccountId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy tài khoản.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Account
    SET IsActive = @IsActive
    WHERE AccountId = @AccountId;
END
GO
/* =========================================================
   65) SP: sp_Admin_Account_ResetPassword
   - admin reset mật khẩu cho account, cập nhật hash + salt mới
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Account_ResetPassword
    @AccountId     INT,
    @PasswordHash  VARBINARY(64),
    @PasswordSalt  VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Account
        WHERE AccountId = @AccountId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy tài khoản.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Account
    SET
        PasswordHash = @PasswordHash,
        PasswordSalt = @PasswordSalt
    WHERE AccountId = @AccountId;
END
GO
/* =========================================================
   66) SP: sp_Admin_Account_Search
   - tìm kiếm tài khoản theo username, displayname
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Account_Search
    @Keyword NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.AccountId,
        a.Username,
        a.DisplayName,
        a.IsActive,
        a.CreatedAt,
        a.LastLoginAt,
        r.RoleName
    FROM dbo.Account a
    LEFT JOIN dbo.AccountRole ar ON a.AccountId = ar.AccountId
    LEFT JOIN dbo.Role r ON ar.RoleId = r.RoleId
    WHERE a.Username LIKE N'%' + @Keyword + N'%'
       OR a.DisplayName LIKE N'%' + @Keyword + N'%'
    ORDER BY a.AccountId DESC;
END
GO
-- Admin thống kê (67- 72) --
/* =========================================================
   67) SP: sp_Admin_Stats_GetOverview
   - lấy số liệu tổng quan toàn hệ thống cho dashboard admin 
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Stats_GetOverview
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (SELECT COUNT(*) FROM dbo.Account) AS TotalAccounts,
        (SELECT COUNT(*) FROM dbo.Account WHERE IsActive = 1) AS ActiveAccounts,
        (SELECT COUNT(*) FROM dbo.Attempt WHERE Status = 1) AS TotalSubmittedAttempts,
        (
            SELECT COUNT(DISTINCT AccountId)
            FROM dbo.Attempt
            WHERE Status = 1
        ) AS TotalUsersWithAttempts,
        (SELECT COUNT(*) FROM dbo.Test WHERE IsActive = 1) AS TotalTests,
        (SELECT COUNT(*) FROM dbo.Question WHERE IsActive = 1) AS TotalQuestions,
        (
            SELECT CAST(AVG(CAST(Score AS DECIMAL(10,2))) AS DECIMAL(10,2))
            FROM dbo.Attempt
            WHERE Status = 1
              AND Score IS NOT NULL
        ) AS AverageScore;
END
GO
/* =========================================================
   68) SP: sp_Admin_Stats_GetAccuracyByPart
   - thống kê toàn hệ thống theo từng part (part nào mạnh/yếu)
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Stats_GetAccuracyByPart
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.PartId,
        p.PartName,
        COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL THEN 1 END) AS TotalAnswered,
        COUNT(CASE WHEN aa.IsCorrect = 1 THEN 1 END) AS CorrectCount,
        COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL AND aa.IsCorrect = 0 THEN 1 END) AS WrongCount,
        CAST(
            CASE
                WHEN COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL THEN 1 END) = 0 THEN 0
                ELSE
                    100.0 * COUNT(CASE WHEN aa.IsCorrect = 1 THEN 1 END)
                    / COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL THEN 1 END)
            END
            AS DECIMAL(5,2)
        ) AS AccuracyPercent
    FROM dbo.Part p
    LEFT JOIN dbo.AttemptQuestion aq
        ON p.PartId = aq.PartId
    LEFT JOIN dbo.Attempt a
        ON aq.AttemptId = a.AttemptId
       AND a.Status = 1
    LEFT JOIN dbo.AttemptAnswer aa
        ON aq.AttemptQuestionId = aa.AttemptQuestionId
    GROUP BY
        p.PartId,
        p.PartName
    ORDER BY
        p.PartId ASC;
END
GO
/* =========================================================
   69) SP: sp_Admin_Stats_GetByTest
   - Thống kê theo từng test
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Stats_GetByTest
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.TestId,
        e.[Year] AS EtsYear,
        t.TestNo,
        t.Title,
        COUNT(a.AttemptId) AS AttemptCount,
        CAST(AVG(CAST(a.Score AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS AverageScore,
        CAST(
            AVG(
                CASE
                    WHEN a.TotalQuestions = 0 THEN 0
                    ELSE 100.0 * a.CorrectCount / a.TotalQuestions
                END
            )
            AS DECIMAL(5,2)
        ) AS AverageAccuracy
    FROM dbo.Test t
    INNER JOIN dbo.EtsSet e
        ON t.EtsId = e.EtsId
    LEFT JOIN dbo.Attempt a
        ON t.TestId = a.TestId
       AND a.Status = 1
    GROUP BY
        t.TestId,
        e.[Year],
        t.TestNo,
        t.Title
    ORDER BY
        e.[Year] DESC,
        t.TestNo ASC;
END
GO
/* =========================================================
   70) SP: sp_Admin_Stats_GetOverviewByAccount
   - admin chọn 1 account, xem tổng quan học tập của account đó
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Stats_GetOverviewByAccount
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Account
        WHERE AccountId = @AccountId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy tài khoản.', 16, 1);
        RETURN;
    END

    SELECT
        ac.AccountId,
        ac.Username,
        ac.DisplayName,
        COUNT(a.AttemptId) AS AttemptCount,
        COUNT(DISTINCT a.TestId) AS DistinctTests,
        CAST(AVG(CAST(a.Score AS DECIMAL(10,2))) AS DECIMAL(10,2)) AS AverageScore,
        MAX(a.FinishedAt) AS LastAttemptAt
    FROM dbo.Account ac
    LEFT JOIN dbo.Attempt a
        ON ac.AccountId = a.AccountId
       AND a.Status = 1
    WHERE ac.AccountId = @AccountId
    GROUP BY
        ac.AccountId,
        ac.Username,
        ac.DisplayName;
END
GO
/* =========================================================
   71) SP: sp_Admin_Stats_GetAccuracyByPartByAccount
   - xem 1 user mạnh/yếu part nào
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Stats_GetAccuracyByPartByAccount
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Account
        WHERE AccountId = @AccountId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy tài khoản.', 16, 1);
        RETURN;
    END

    SELECT
        p.PartId,
        p.PartName,
        COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL THEN 1 END) AS TotalAnswered,
        COUNT(CASE WHEN aa.IsCorrect = 1 THEN 1 END) AS CorrectCount,
        COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL AND aa.IsCorrect = 0 THEN 1 END) AS WrongCount,
        CAST(
            CASE
                WHEN COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL THEN 1 END) = 0 THEN 0
                ELSE
                    100.0 * COUNT(CASE WHEN aa.IsCorrect = 1 THEN 1 END)
                    / COUNT(CASE WHEN aa.ChosenAnswerId IS NOT NULL THEN 1 END)
            END
            AS DECIMAL(5,2)
        ) AS AccuracyPercent
    FROM dbo.Part p
    LEFT JOIN dbo.AttemptQuestion aq
        ON p.PartId = aq.PartId
    LEFT JOIN dbo.Attempt a
        ON aq.AttemptId = a.AttemptId
       AND a.Status = 1
       AND a.AccountId = @AccountId
    LEFT JOIN dbo.AttemptAnswer aa
        ON aq.AttemptQuestionId = aa.AttemptQuestionId
    GROUP BY
        p.PartId,
        p.PartName
    ORDER BY
        p.PartId ASC;
END
GO
/* =========================================================
   72) SP: sp_Admin_Stats_GetRecentAttemptsByAccount
   - hiển thị danh sách lần làm gần đây của 1 account
   ========================================================= */
CREATE OR ALTER PROCEDURE dbo.sp_Admin_Stats_GetRecentAttemptsByAccount
    @AccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Account
        WHERE AccountId = @AccountId
    )
    BEGIN
        RAISERROR(N'Không tìm thấy tài khoản.', 16, 1);
        RETURN;
    END

    SELECT
        a.AttemptId,
        a.TestId,
        e.[Year] AS EtsYear,
        t.TestNo,
        t.Title AS TestTitle,
        a.StartedAt,
        a.FinishedAt,
        a.Score,
        a.CorrectCount,
        a.WrongCount,
        a.SkippedCount
    FROM dbo.Attempt a
    INNER JOIN dbo.Test t
        ON a.TestId = t.TestId
    INNER JOIN dbo.EtsSet e
        ON t.EtsId = e.EtsId
    WHERE a.AccountId = @AccountId
      AND a.Status = 1
    ORDER BY a.StartedAt DESC;
END
GO
---------------------------------------------
-- PHẦN CHỈNH SỬA HỆ THỐNG --
-- 1) Sửa index sai cột
DROP INDEX IF EXISTS IX_AttemptQuestion_Attempt_Order ON dbo.AttemptQuestion;
GO

CREATE INDEX IX_AttemptQuestion_Attempt_Order
ON dbo.AttemptQuestion(AttemptId, OrderNo);
GO

-- 2) Mỗi câu chỉ có tối đa 1 đáp án đúng
CREATE UNIQUE INDEX UX_Answer_OneCorrectPerQuestion
ON dbo.Answer(QuestionId)
WHERE IsCorrect = 1;
GO

-- 3) QuestionOption không được trùng DisplayOrder
ALTER TABLE dbo.QuestionOption
ADD CONSTRAINT UQ_QuestionOption_Question_DisplayOrder
UNIQUE (QuestionId, DisplayOrder);
GO

-- 4) AttemptOption không được trùng DisplayOrder
ALTER TABLE dbo.AttemptOption
ADD CONSTRAINT UQ_AttemptOption_AttemptQuestion_DisplayOrder
UNIQUE (AttemptQuestionId, DisplayOrder);
GO

ALTER TABLE dbo.QuestionGroup
DROP CONSTRAINT CK_QuestionGroup_GroupType;
GO

ALTER TABLE dbo.QuestionGroup
ADD CONSTRAINT CK_QuestionGroup_GroupType
CHECK (GroupType IN (
    'SINGLE',
    'CONVERSATION',
    'PASSAGE',
    'SINGLE_PASSAGE',
    'DOUBLE_PASSAGE',
    'TRIPLE_PASSAGE'
));
GO
--- PHẦN SEED DỮ LIỆU ----

------------------------------------------------------------
-- SEED DỮ LIỆU BAN ĐẦU: ROLE, PART
------------------------------------------------------------

-- Seed ROLE
IF NOT EXISTS (SELECT 1 FROM dbo.Role WHERE RoleName = 'USER')
    INSERT INTO dbo.Role(RoleName) VALUES ('USER');

IF NOT EXISTS (SELECT 1 FROM dbo.Role WHERE RoleName = 'ADMIN')
    INSERT INTO dbo.Role(RoleName) VALUES ('ADMIN');
GO

-- Seed PART (7 part)
IF NOT EXISTS (SELECT 1 FROM dbo.Part WHERE PartId = 1)
BEGIN
    INSERT INTO dbo.Part(PartId, PartName, HasAudio, HasImage, Section) VALUES
    (1, 'Part 1', 1, 1, 1),
    (2, 'Part 2', 1, 0, 1),
    (3, 'Part 3', 1, 0, 1),
    (4, 'Part 4', 1, 0, 1),
    (5, 'Part 5', 0, 0, 2),
    (6, 'Part 6', 0, 0, 2),
    (7, 'Part 7', 0, 0, 2);
END
GO
------------------------------
------------------------------------------------------------
-- SEED DỮ LIỆU PART1
------------------------------------------------------------
USE TOEIC_PracticeDB;
GO
BEGIN TRAN;

BEGIN TRY
    DECLARE @EtsId INT;
    DECLARE @TestId INT;
    DECLARE @GroupId1 INT, @GroupId2 INT;
    DECLARE @QuestionId1 INT, @QuestionId2 INT;

    DECLARE @A1 INT, @B1 INT, @C1 INT, @D1 INT;
    DECLARE @A2 INT, @B2 INT, @C2 INT, @D2 INT;
-- ETS --
IF NOT EXISTS (SELECT 1 FROM dbo.EtsSet WHERE [Year] = 2024)
    BEGIN
        INSERT INTO dbo.EtsSet([Year], Title)
        VALUES (2024, N'ETS 2024');
    END

    SELECT @EtsId = EtsId
    FROM dbo.EtsSet
    WHERE [Year] = 2024;   
-- Test --
IF NOT EXISTS (SELECT 1 FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1)
BEGIN
    INSERT INTO dbo.Test(EtsId, TestNo, Title)
    VALUES (@EtsId, 1, N'Test 1');
END
SELECT @TestId = TestId FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1;

-- Tạo 1 group Part 1 --
INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        1,
        'SINGLE',
        'Part1/2024_T1_P1_Q1.mp3',
        'Part1/2024_T1_P1_Q1.png',
        NULL,
        1
    );
    SET @GroupId1 = SCOPE_IDENTITY();
 -- Tạo 1 question -- 
    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId1,
        N'Look at the picture in your textbook',
        N'(A) The woman is talking on the phone.(Người phụ nữ đang nói chuyện điện thoại)
        (B) The woman is using her cell phone. (Người phụ nữ đang sử dụng điện thoại di động)
        (C) The woman is typing on the laptop. (Người phụ nữ đang gõ trên máy tính xách tay)
        (D) The woman is writing in her notebook. (Người phụ nữ đang viết vào sổ tay của mình)',
        1
    );

    SET @QuestionId1 = SCOPE_IDENTITY();
-- Tạo 4 answers --
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@QuestionId1, N'The woman is talking on the phone.', 1),   
    (@QuestionId1, N'The woman is using her cell phone.', 0),
    (@QuestionId1, N'The woman is typing on the laptop.', 0),
    (@QuestionId1, N'The woman is writing in her notebook.', 0);

    SELECT @A1 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId1 AND AnswerText = N'The woman is talking on the phone.';
    SELECT @B1 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId1 AND AnswerText = N'The woman is using her cell phone.';
    SELECT @C1 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId1 AND AnswerText = N'The woman is typing on the laptop.';
    SELECT @D1 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId1 AND AnswerText = N'The woman is writing in her notebook.';

    INSERT INTO dbo.QuestionOption
    (
        QuestionId,
        AnswerId,
        OptionLabel,
        DisplayOrder
    )
    VALUES
    (@QuestionId1, @A1, 'A', 1),
    (@QuestionId1, @B1, 'B', 2),
    (@QuestionId1, @C1, 'C', 3),
    (@QuestionId1, @D1, 'D', 4);
-- GROUP 2 - Part 1 --
INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        1,
        'SINGLE',
        'Part1/2024_T1_P1_Q2.mp3',
        'Part1/2024_T1_P1_Q2.png',
        NULL,
        2
    );

    SET @GroupId2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId2,
        N'Look at the picture in your textbook',
        N'(A) The woman is cooking some bacon.(Người phụ nữ đang nấu một ít thịt xông khói)
        (B) The woman is baking a cake.(Người phụ nữ đang nướng bánh)
        (C) The woman is preparing for dinner.(Người phụ nữ đang chuẩn bị cho bữa tối)
        (D) The woman is frying some fish.( Người phụ nữ đang chiên một ít cá)',
        1
    );

    SET @QuestionId2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@QuestionId2, N'The woman is cooking some bacon.', 1),
    (@QuestionId2, N'The woman is baking a cake.', 0),
    (@QuestionId2, N'The woman is preparing for dinner.', 0),
    (@QuestionId2, N'The woman is frying some fish.', 0);

    SELECT @A2 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId2 AND AnswerText = N'The woman is cooking some bacon.';
    SELECT @B2 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId2 AND AnswerText = N'The woman is baking a cake.';
    SELECT @C2 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId2 AND AnswerText = N'The woman is preparing for dinner.';
    SELECT @D2 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId2 AND AnswerText = N'The woman is frying some fish.';

    INSERT INTO dbo.QuestionOption
    (
        QuestionId,
        AnswerId,
        OptionLabel,
        DisplayOrder
    )
    VALUES
    (@QuestionId2, @A2, 'A', 1),
    (@QuestionId2, @B2, 'B', 2),
    (@QuestionId2, @C2, 'C', 3),
    (@QuestionId2, @D2, 'D', 4);

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    THROW;
END CATCH;
GO
------------------------------------------------------------
-- SEED DỮ LIỆU PART2
------------------------------------------------------------
USE TOEIC_PracticeDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRAN;

BEGIN TRY
    DECLARE @EtsId INT;
    DECLARE @TestId INT;

    DECLARE @GroupId1 INT, @GroupId2 INT;
    DECLARE @QuestionId1 INT, @QuestionId2 INT;

    DECLARE @A1 INT, @B1 INT, @C1 INT, @D1 INT;
    DECLARE @A2 INT, @B2 INT, @C2 INT, @D2 INT;

    /* =========================================================
       ETS 2024
       ========================================================= */
    IF NOT EXISTS (SELECT 1 FROM dbo.EtsSet WHERE [Year] = 2024)
    BEGIN
        INSERT INTO dbo.EtsSet([Year], Title)
        VALUES (2024, N'ETS 2024');
    END

    SELECT @EtsId = EtsId
    FROM dbo.EtsSet
    WHERE [Year] = 2024;

    /* =========================================================
       TEST 1
       ========================================================= */
    IF NOT EXISTS (SELECT 1 FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1)
    BEGIN
    INSERT INTO dbo.Test(EtsId, TestNo, Title)
    VALUES (@EtsId, 1, N'Test 1');
    END
    SELECT @TestId = TestId FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1;

    /* =========================================================
       GROUP 1 - Part 2
       ========================================================= */
    INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        2,
        'SINGLE',
        'Part2/2024_T1_P2_Q7.mp3',
        NULL,
        NULL,
        1
    );

    SET @GroupId1 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId1,
        N'Where was the company picnic held??',
        N'7. Chuyến dã ngoại của công ty được tổ chức ở đâu?
        (A) Vào tháng 4.
        (B) Đồ uống giải khát sẽ được cung cấp.
        (C) Tại một công viên cạnh hồ.',
        1
    );

    SET @QuestionId1 = SCOPE_IDENTITY();

    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@QuestionId1, N'In April.', 0),
    (@QuestionId1, N'Refreshments will be provided.', 0),
    (@QuestionId1, N'At a park next to a lake.', 1);
    

    SELECT @A1 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId1 AND AnswerText = N'In April.';
    SELECT @B1 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId1 AND AnswerText = N'Refreshments will be provided.';
    SELECT @C1 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId1 AND AnswerText = N'At a park next to a lake.';
    

    INSERT INTO dbo.QuestionOption
    (
        QuestionId,
        AnswerId,
        OptionLabel,
        DisplayOrder
    )
    VALUES
    (@QuestionId1, @A1, 'A', 1),
    (@QuestionId1, @B1, 'B', 2),
    (@QuestionId1, @C1, 'C', 3);
    

    /* =========================================================
       GROUP 2 - Part 2
       ========================================================= */
    INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        2,
        'SINGLE',
        'Part2/2024_T1_P2_Q8.mp3',
        NULL,
        NULL,
        2
    );

    SET @GroupId2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId2,
        N'Who is working at the front desk today?',
        N'8. Hôm nay ai làm việc ở quầy lễ tân?
        (A) Đó là một yêu cầu khó.
        (B) Đó là Katie Miller.
        (C) Hãy dọn chỗ trên bàn của bạn.',
        1
    );

    SET @QuestionId2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@QuestionId2, N'That is a difficult request.', 0),
    (@QuestionId2, N'It is Katie Miller.', 1),
    (@QuestionId2, N'Make room on your desk.', 0);
    

    SELECT @A2 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId2 AND AnswerText = N'That is a difficult request.';
    SELECT @B2 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId2 AND AnswerText = N'It is Katie Miller.';
    SELECT @C2 = AnswerId FROM dbo.Answer WHERE QuestionId = @QuestionId2 AND AnswerText = N'Make room on your desk.';
    

    INSERT INTO dbo.QuestionOption
    (
        QuestionId,
        AnswerId,
        OptionLabel,
        DisplayOrder
    )
    VALUES
    (@QuestionId2, @A2, 'A', 1),
    (@QuestionId2, @B2, 'B', 2),
    (@QuestionId2, @C2, 'C', 3);
    
    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    THROW;
END CATCH;
GO
------------------------------------------------------------
-- SEED DỮ LIỆU PART3
------------------------------------------------------------
USE TOEIC_PracticeDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRAN;

BEGIN TRY
    DECLARE @EtsId INT;
    DECLARE @TestId INT;
    DECLARE @GroupId INT;

    DECLARE @Q1 INT, @Q2 INT, @Q3 INT;

    DECLARE @Q1A INT, @Q1B INT, @Q1C INT, @Q1D INT;
    DECLARE @Q2A INT, @Q2B INT, @Q2C INT, @Q2D INT;
    DECLARE @Q3A INT, @Q3B INT, @Q3C INT, @Q3D INT;

    /* =========================================================
       ETS 2024
       ========================================================= */
    IF NOT EXISTS (SELECT 1 FROM dbo.EtsSet WHERE [Year] = 2024)
    BEGIN
        INSERT INTO dbo.EtsSet([Year], Title)
        VALUES (2024, N'ETS 2024');
    END

    SELECT @EtsId = EtsId
    FROM dbo.EtsSet
    WHERE [Year] = 2024;

    /* =========================================================
       TEST_1
       ========================================================= */
    IF NOT EXISTS (SELECT 1 FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1)
    BEGIN
    INSERT INTO dbo.Test(EtsId, TestNo, Title)
    VALUES (@EtsId, 1, N'Test 1');
    END
    SELECT @TestId = TestId FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1;
    /* =========================================================
       STEP 3: Xóa dữ liệu mẫu cũ của Part 3 trong Test 94
       ========================================================= */
    DELETE qo
    FROM dbo.QuestionOption qo
    INNER JOIN dbo.Question q
        ON qo.QuestionId = q.QuestionId
    INNER JOIN dbo.QuestionGroup g
        ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 3;

    DELETE a
    FROM dbo.Answer a
    INNER JOIN dbo.Question q
        ON a.QuestionId = q.QuestionId
    INNER JOIN dbo.QuestionGroup g
        ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 3;

    DELETE q
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g
        ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 3;

    DELETE dbo.QuestionGroup
    WHERE TestId = @TestId
      AND PartId = 3;
    /* =========================================================
       Tạo 1 group conversation cho Part 3
       ========================================================= */
    INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        3,
        'CONVERSATION',
        'Part3/2024_T1_P3_Q32_33_34.mp3',
        NULL,
        NULL,
        1
    );

    SET @GroupId = SCOPE_IDENTITY();

    /* =========================================================
       Tạo 3 questions trong cùng group
       ========================================================= */
    INSERT INTO dbo.Question (GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        N'What are the speakers mainly discussing?',
        N'32. Những người nói chủ yếu thảo luận về vấn đề gì?
        A. Một buổi hội thảo đào tạo.
        B. Việc lắp đặt một chiếc tivi.
        C. Ngày thuyết trình.
        D. Nâng cấp phần mềm.',
        1
    );
    SET @Q1 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question (GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        N'What is the problem?',
        N'33. Vấn đề là gì?
        A. Các công cụ cần thiết không có sẵn.
        B. Văn phòng đóng cửa.
        C. Tường quá yếu.
        D. Số điện thoại bị sai.',
        2
    );
    SET @Q2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question (GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        N'What most likely will the man do first tomorrow?',
        N'34. Người đàn ông có nhiều khả năng sẽ làm gì đầu tiên vào ngày mai?
        A. Đặt mua bộ phận thay thế.
        B. Tham khảo sách hướng dẫn.
        C. Liên hệ với người phụ nữ.
        D. Điền vào lệnh làm việc.',
        3
    );
    SET @Q3 = SCOPE_IDENTITY();

    /* =========================================================
       Answers cho Question 1
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q1, N'A training seminar.', 0),
    (@Q1, N'The installation of a television.', 1),
    (@Q1, N'The date of a presentation.', 0),
    (@Q1, N'A software upgrade.', 0);

    SELECT @Q1A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'A training seminar.';
    SELECT @Q1B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'The installation of a television.';
    SELECT @Q1C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'The date of a presentation.';
    SELECT @Q1D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'A software upgrade.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q1, @Q1A, 'A', 1),
    (@Q1, @Q1B, 'B', 2),
    (@Q1, @Q1C, 'C', 3),
    (@Q1, @Q1D, 'D', 4);

    /* =========================================================
       Answers cho Question 2
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q2, N'The necessary tools are unavailable.', 1),
    (@Q2, N'The office is closed.', 0),
    (@Q2, N'The wall is too weak.', 0),
    (@Q2, N'The phone number was wrong.', 0);

    SELECT @Q2A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'The necessary tools are unavailable.';
    SELECT @Q2B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'The office is closed.';
    SELECT @Q2C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'The wall is too weak.';
    SELECT @Q2D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'The phone number was wrong.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q2, @Q2A, 'A', 1),
    (@Q2, @Q2B, 'B', 2),
    (@Q2, @Q2C, 'C', 3),
    (@Q2, @Q2D, 'D', 4);

    /* =========================================================
       Answers cho Question 3
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q3, N'Order a replacement part.', 0),
    (@Q3, N'Consult an instruction manual.', 0),
    (@Q3, N'Contact the woman.', 1),
    (@Q3, N'Fill out a work order.', 0);

    SELECT @Q3A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Order a replacement part.';
    SELECT @Q3B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Consult an instruction manual.';
    SELECT @Q3C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Contact the woman.';
    SELECT @Q3D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Fill out a work order.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q3, @Q3A, 'A', 1),
    (@Q3, @Q3B, 'B', 2),
    (@Q3, @Q3C, 'C', 3),
    (@Q3, @Q3D, 'D', 4);

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;
    THROW;
END CATCH;
GO
----
USE TOEIC_PracticeDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRAN;

BEGIN TRY
    DECLARE @EtsId INT;
    DECLARE @TestId INT;
    DECLARE @GroupId INT;

    DECLARE @Q5 INT, @Q6 INT, @Q7 INT;

    DECLARE @Q5A INT, @Q5B INT, @Q5C INT, @Q5D INT;
    DECLARE @Q6A INT, @Q6B INT, @Q6C INT, @Q6D INT;
    DECLARE @Q7A INT, @Q7B INT, @Q7C INT, @Q7D INT;

    IF NOT EXISTS (SELECT 1 FROM dbo.EtsSet WHERE [Year] = 2024)
    BEGIN
        INSERT INTO dbo.EtsSet([Year], Title)
        VALUES (2024, N'ETS 2024');
    END
    -- ETS --
    SELECT @EtsId = EtsId
    FROM dbo.EtsSet
    WHERE [Year] = 2024;
    -- TEST_1 --
    IF NOT EXISTS (SELECT 1 FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1)
    BEGIN
    INSERT INTO dbo.Test(EtsId, TestNo, Title)
    VALUES (@EtsId, 1, N'Test 1');
    END
    SELECT @TestId = TestId FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1;
    --
    INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        3,
        'CONVERSATION',
        'Part3/2024_T1_P3_Q68_69_70.mp3',
        'Part3/2024_T1_P3_Q68_69_70.png',
        NULL,
        2
    );

    SET @GroupId = SCOPE_IDENTITY();

    /* =========================================================
       Tạo 3 câu hỏi trong cùng group
       ========================================================= */
    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId,
        N'What are the speakers discussing?',
        N'68. Những người nói đang thảo luận về điều gì?
        A. Hệ thống GPS của họ.
        B. Nên ghé thăm quán cà phê nào.
        C. Cambridge cách căn hộ của họ bao xa.
        D. Con đường đi làm nhanh nhất.',
        1
    );
    SET @Q5 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId,
        N'What does the woman want to do?',
        N'69. Người phụ nữ muốn làm gì?
        A. Tiếp tục thua trò chơi.
        B. Kiếm được nhiều tiền hơn anh ấy.
        C. Đi làm nhanh hơn anh ấy.
        D. Tham gia một cuộc đua xe.',
        2
    );
    SET @Q6 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId,
        N'Look at the list. Which shop does the man most likely stop at?',
        N'70. Nhìn vào danh sách. Người đàn ông thường dừng lại ở cửa hàng nào nhất?
        A. Coffee Bean.
        B. Tea shop.
        C. Java the Cup.
        D. Jake is Diner.',
        3
    );
    SET @Q7 = SCOPE_IDENTITY();

    /* =========================================================
       STEP 6: Answers cho Question 1
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q5, N'Their GPS systems.', 0),
    (@Q5, N'Which coffee shop to visit.', 0),
    (@Q5, N'How far Cambridge is from their apartments.', 0),
    (@Q5, N'The fastest route to work.', 1);

    SELECT @Q5A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q5 AND AnswerText = N'Their GPS systems.';
    SELECT @Q5B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q5 AND AnswerText = N'Which coffee shop to visit.';
    SELECT @Q5C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q5 AND AnswerText = N'How far Cambridge is from their apartments.';
    SELECT @Q5D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q5 AND AnswerText = N'The fastest route to work.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q5, @Q5A, 'A', 1),
    (@Q5, @Q5B, 'B', 2),
    (@Q5, @Q5C, 'C', 3),
    (@Q5, @Q5D, 'D', 4);

    /* =========================================================
       STEP 7: Answers cho Question 2
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q6, N'Keep losing the game.', 0),
    (@Q6, N'Make more money than he does.', 0),
    (@Q6, N'Get to work faster than he does.', 1),
    (@Q6, N'Participate in a car race.', 0);

    SELECT @Q6A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q6 AND AnswerText = N'Keep losing the game.';
    SELECT @Q6B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q6 AND AnswerText = N'Make more money than he does.';
    SELECT @Q6C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q6 AND AnswerText = N'Get to work faster than he does.';
    SELECT @Q6D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q6 AND AnswerText = N'Participate in a car race.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q6, @Q6A, 'A', 1),
    (@Q6, @Q6B, 'B', 2),
    (@Q6, @Q6C, 'C', 3),
    (@Q6, @Q6D, 'D', 4);

    /* =========================================================
       STEP 8: Answers cho Question 3
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q7, N'Coffee Bean.', 0),
    (@Q7, N'Tea shop.', 0),
    (@Q7, N'Java the Cup.', 1),
    (@Q7, N'Jake is Diner.', 0);

    SELECT @Q7A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q7 AND AnswerText = N'Coffee Bean.';
    SELECT @Q7B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q7 AND AnswerText = N'Tea shop.';
    SELECT @Q7C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q7 AND AnswerText = N'Java the Cup.';
    SELECT @Q7D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q7 AND AnswerText = N'Jake is Diner.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q7, @Q7A, 'A', 1),
    (@Q7, @Q7B, 'B', 2),
    (@Q7, @Q7C, 'C', 3),
    (@Q7, @Q7D, 'D', 4);

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;
    THROW;
END CATCH;
GO
/* =========================================================
       SEED PART_4
========================================================= */
USE TOEIC_PracticeDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRAN;

BEGIN TRY
    DECLARE @EtsId INT;
    DECLARE @TestId INT;
    DECLARE @GroupId INT;
    DECLARE @NextOrderNo INT;

    DECLARE @Q1 INT, @Q2 INT, @Q3 INT;

    DECLARE @Q1A INT, @Q1B INT, @Q1C INT, @Q1D INT;
    DECLARE @Q2A INT, @Q2B INT, @Q2C INT, @Q2D INT;
    DECLARE @Q3A INT, @Q3B INT, @Q3C INT, @Q3D INT;

    /* =========================================================
       ETS 2024
       ========================================================= */
    IF NOT EXISTS (SELECT 1 FROM dbo.EtsSet WHERE [Year] = 2024)
    BEGIN
        INSERT INTO dbo.EtsSet([Year], Title)
        VALUES (2024, N'ETS 2024');
    END

    SELECT @EtsId = EtsId
    FROM dbo.EtsSet
    WHERE [Year] = 2024;

    /* =========================================================
       TEST_1
       ========================================================= */
    IF NOT EXISTS (SELECT 1 FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1)
    BEGIN
    INSERT INTO dbo.Test(EtsId, TestNo, Title)
    VALUES (@EtsId, 1, N'Test 1');
    END
    SELECT @TestId = TestId FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1;

    /* =========================================================
       STEP 3: Xóa dữ liệu mẫu cũ của Part 4 trong Test 1
       ========================================================= */
    DELETE qo
    FROM dbo.QuestionOption qo
    INNER JOIN dbo.Question q
        ON qo.QuestionId = q.QuestionId
    INNER JOIN dbo.QuestionGroup g
        ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 4;

    DELETE a
    FROM dbo.Answer a
    INNER JOIN dbo.Question q
        ON a.QuestionId = q.QuestionId
    INNER JOIN dbo.QuestionGroup g
        ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 4;

    DELETE q
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g
        ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 4;

    DELETE dbo.QuestionGroup
    WHERE TestId = @TestId
      AND PartId = 4;

    /* =========================================================
       STEP 4: Lấy OrderNo tiếp theo
       ========================================================= */
    SELECT @NextOrderNo = ISNULL(MAX(OrderNo), 0) + 1
    FROM dbo.QuestionGroup
    WHERE TestId = @TestId
      AND PartId = 4;

    /* =========================================================
       STEP 5: Tạo 1 group Part 4
       - có audio
       - có thể có image minh họa
       ========================================================= */
    INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        4,
        'CONVERSATION',
        'Part4/2024_T1_P4_Q98_99_100.mp3',
        'Part4/2024_T1_P4_Q98_99_100.png',
        NULL,
        @NextOrderNo
    );

    SET @GroupId = SCOPE_IDENTITY();

    /* =========================================================
       STEP 6: Tạo 3 questions
       ========================================================= */
    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId,
        N'What are the listeners training to be?',
        N'98. Người nghe được đào tạo để trở thành gì?
        A. Công nhân nhà máy.
        B. Chủ cửa hàng.
        C. Đầu bếp nhà hàng.
        D. Nhân viên y tế.',
        1
    );
    SET @Q1 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId,
        N'According to the speaker, what will the listeners enjoy doing?',
        N'99. Theo người nói, người nghe sẽ thích làm gì?
        A. Làm việc với các đầu bếp nổi tiếng.
        B. Trở thành đầu bếp nổi tiếng.
        C. Sử dụng dụng cụ nhà bếp.
        D. Làm việc với nhau.',
        2
    );
    SET @Q2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question
    (
        GroupId,
        QuestionText,
        Explanation,
        OrderInGroup
    )
    VALUES
    (
        @GroupId,
        N'Look at the graphic. On what day will the listeners learn food safety and hygiene?',
        N'100. Nhìn vào đồ họa. Người nghe sẽ được tìm hiểu về an toàn vệ sinh thực phẩm vào ngày nào?
        A. Thứ ba.
        B. Thứ tư.
        C. Thứ năm.
        D. Thứ sáu.',
        3
    );
    SET @Q3 = SCOPE_IDENTITY();

    /* =========================================================
       STEP 7: Answers cho Question 1
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q1, N'Factory workers.', 0),
    (@Q1, N'Store owners.', 0),
    (@Q1, N'Restaurant chefs.', 1),
    (@Q1, N'Medical workers.', 0);

    SELECT @Q1A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'Factory workers.';
    SELECT @Q1B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'Store owners.';
    SELECT @Q1C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'Restaurant chefs.';
    SELECT @Q1D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'Medical workers.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q1, @Q1A, 'A', 1),
    (@Q1, @Q1B, 'B', 2),
    (@Q1, @Q1C, 'C', 3),
    (@Q1, @Q1D, 'D', 4);

    /* =========================================================
       STEP 8: Answers cho Question 2
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q2, N'Working with the celebrity chefs.', 1),
    (@Q2, N'Becoming a celebrity chef.', 0),
    (@Q2, N'Using the kitchen tools.', 0),
    (@Q2, N'Working with each other.', 0);

    SELECT @Q2A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Working with the celebrity chefs.';
    SELECT @Q2B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Becoming a celebrity chef.';
    SELECT @Q2C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Using the kitchen tools.';
    SELECT @Q2D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Working with each other.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q2, @Q2A, 'A', 1),
    (@Q2, @Q2B, 'B', 2),
    (@Q2, @Q2C, 'C', 3),
    (@Q2, @Q2D, 'D', 4);

    /* =========================================================
       STEP 9: Answers cho Question 3
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q3, N'Tuesday.', 0),
    (@Q3, N'Wednesday.', 0),
    (@Q3, N'Thursday.', 1),
    (@Q3, N'Friday.', 0);

    SELECT @Q3A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Tuesday.';
    SELECT @Q3B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Wednesday.';
    SELECT @Q3C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Thursday.';
    SELECT @Q3D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Friday.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q3, @Q3A, 'A', 1),
    (@Q3, @Q3B, 'B', 2),
    (@Q3, @Q3C, 'C', 3),
    (@Q3, @Q3D, 'D', 4);

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;
    THROW;
END CATCH;
GO
--

-- ===== SEED TỐI THIỂU ĐỂ TEST PART 5 (1 ETS + 1 TEST + 1 GROUP + 1 Q + 4 A) 
DECLARE @Year INT = 2024;
DECLARE @EtsId INT;
DECLARE @TestId INT;
DECLARE @GroupId INT;
DECLARE @QuestionId INT;

-- 0) Đảm bảo có Part 5 (nếu PartId=5 chưa tồn tại)
IF NOT EXISTS (SELECT 1 FROM dbo.Part WHERE PartId = 5)
BEGIN
    INSERT INTO dbo.Part(PartId, PartName, HasAudio, HasImage, Section)
    VALUES (5, 'Part 5', 0, 0, 2);
END

-- 1) ETS
IF NOT EXISTS (SELECT 1 FROM dbo.EtsSet WHERE [Year] = @Year)
BEGIN
    INSERT INTO dbo.EtsSet([Year], Title)
    VALUES (@Year, N'ETS ' + CAST(@Year AS NVARCHAR(10)));
END

SELECT @EtsId = EtsId FROM dbo.EtsSet WHERE [Year] = @Year;

-- 2) Test
IF NOT EXISTS (SELECT 1 FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1)
BEGIN
    INSERT INTO dbo.Test(EtsId, TestNo, Title)
    VALUES (@EtsId, 1, N'Test 1');
END

SELECT @TestId = TestId FROM dbo.Test WHERE EtsId = @EtsId AND TestNo = 1;

-- 3) Group Part 5
IF NOT EXISTS (SELECT 1 FROM dbo.QuestionGroup WHERE TestId=@TestId AND PartId=5 AND OrderNo=1)
BEGIN
    INSERT INTO dbo.QuestionGroup(TestId, PartId, GroupType, AudioPath, ImagePath, PassageText, OrderNo)
    VALUES (@TestId, 5, 'SINGLE', NULL, NULL, NULL, 1);
END

SELECT @GroupId = GroupId
FROM dbo.QuestionGroup
WHERE TestId=@TestId AND PartId=5 AND OrderNo=1;

-- 4) Question
IF NOT EXISTS (SELECT 1 FROM dbo.Question WHERE GroupId=@GroupId AND OrderInGroup=1)
BEGIN
    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (@GroupId,
     N'She ____ to work by bus every day.',
     N'Dùng "goes" với chủ ngữ số ít (She goes).',
     1);
END

SELECT @QuestionId = QuestionId
FROM dbo.Question
WHERE GroupId=@GroupId AND OrderInGroup=1;

-- 5) Answers (4 đáp án)
IF NOT EXISTS (SELECT 1 FROM dbo.Answer WHERE QuestionId=@QuestionId)
BEGIN
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect) VALUES
    (@QuestionId, N'go', 0),
    (@QuestionId, N'going', 0),
    (@QuestionId, N'went', 0),
    (@QuestionId, N'goes', 1);
END

-- 6) (Tuỳ chọn) QuestionOption A/B/C/D
IF NOT EXISTS (SELECT 1 FROM dbo.QuestionOption WHERE QuestionId=@QuestionId)
BEGIN
    ;WITH A AS
    (
        SELECT AnswerId, ROW_NUMBER() OVER (ORDER BY AnswerId) rn
        FROM dbo.Answer
        WHERE QuestionId = @QuestionId
    )
    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    SELECT
        @QuestionId,
        AnswerId,
        CASE rn WHEN 1 THEN 'A' WHEN 2 THEN 'B' WHEN 3 THEN 'C' WHEN 4 THEN 'D' END,
        CAST(rn AS TINYINT)
    FROM A
    WHERE rn BETWEEN 1 AND 4;
END
------------------------------
-- ===== SEED TỐI THIỂU PART 6 (1 group passage + 1 câu + 4 đáp án) =====
USE TOEIC_PracticeDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRAN;

BEGIN TRY
    DECLARE @EtsId INT = 2024
    DECLARE @TestId INT = 1;   -- đổi lại đúng TestId bạn muốn seed

    DECLARE @NextOrderNo INT;
    DECLARE @GroupId INT;

    DECLARE @Q1 INT, @Q2 INT, @Q3 INT, @Q4 INT;

    DECLARE @Q1A INT, @Q1B INT, @Q1C INT, @Q1D INT;
    DECLARE @Q2A INT, @Q2B INT, @Q2C INT, @Q2D INT;
    DECLARE @Q3A INT, @Q3B INT, @Q3C INT, @Q3D INT;
    DECLARE @Q4A INT, @Q4B INT, @Q4C INT, @Q4D INT;

    /* =========================================================
       STEP 1: Lấy OrderNo tiếp theo của Part 6 trong test
       ========================================================= */
    SELECT @NextOrderNo = ISNULL(MAX(OrderNo), 0) + 1
    FROM dbo.QuestionGroup
    WHERE TestId = @TestId
      AND PartId = 6;

    /* =========================================================
       STEP 2: Tạo 1 group Part 6
       ========================================================= */
    INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        6,
        'PASSAGE',
        NULL,
        NULL,
        N'Thank you for shopping at Larson is China. Our products are known for their modern and unique patterns and color combinations, as well as _____(135) and strength. _____(136). Please note, however, that repeated drops and rough handling will _____(137) eventual breakage. We suggest you store them carefully and that you do not use harsh chemicals, steel sponges, or _____(138) scrubbing when cleaning them. Please visit our website at www.larsonchina.com for information about handling and care or call us at 555-1234 if you have any questions or concerns.',
        @NextOrderNo
    );

    SET @GroupId = SCOPE_IDENTITY();

    /* =========================================================
       STEP 3: Tạo 4 câu hỏi
       ========================================================= */
    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        NULL,
        N'(135) Chúng ta thấy sau chỗ trống có "and strength". Như vậy nghĩa là chỗ trống và "strength" đang được nối với nhau bởi liên từ "and". Vì vậy, từ trong chỗ trống phải cùng từ loại với "strength"."Strength" là danh từ, vì vậy, cần điền danh từ --> lựa chọn giữa "durability" và "duration".Dựa vào nghĩa, chọn "durability".',
        1
    );
    SET @Q1 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        NULL,
        N'(136) A. Đồ dùng và đồ dùng bằng bạc của Larson rất phù hợp với bộ đồ ăn.
        B. Dòng sản phẩm phổ biến nhất của chúng tôi, Spring Flower China, đã bán hết ở hầu hết các địa điểm.
        C. Hãy ghé thăm cửa hàng của chúng tôi để xem các sản phẩm đẹp khác của chúng tôi.
        D. Chúng an toàn với máy rửa chén và lò vi sóng và chúng tôi tin tưởng rằng bạn sẽ sử dụng chúng trong nhiều năm tới.
        -------
        Câu trước đó nói về những sản phẩm này bền, câu này nói rõ hơn là chúng đủ bền để dùng với máy rửa bát đĩa và lò vi ba, và đồng thời có thể dùng được nhiều năm.',
        2
    );
    SET @Q2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        NULL,
        N'(137) A. result in: dẫn đến
        B. occur to: xảy ra
        C. ending at: kết thúc tại
        D. stop with: dừng lại với
        -------
        Dựa vào ý nghĩa, chọn "result in".',
        3
    );
    SET @Q3 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        NULL,
        N'(138) A. ambitious (adj): đầy tham vọng
        B. combative (adj): hiếu chiến
        C. aggressive (adj): mạnh mẽ
        D. complacent (adj): tự mãn
        -------
        Dựa vào ý nghĩa, chọn "aggressive".',
        4
    );
    SET @Q4 = SCOPE_IDENTITY();

    /* =========================================================
       STEP 4: Answers cho Question 1
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q1, N'durable', 0),
    (@Q1, N'durability', 1),
    (@Q1, N'duration', 0),
    (@Q1, N'during', 0);

    SELECT @Q1A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'durable';
    SELECT @Q1B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'durability';
    SELECT @Q1C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'duration';
    SELECT @Q1D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'during';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q1, @Q1A, 'A', 1),
    (@Q1, @Q1B, 'B', 2),
    (@Q1, @Q1C, 'C', 3),
    (@Q1, @Q1D, 'D', 4);

    /* =========================================================
       STEP 5: Answers cho Question 2
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q2, N'Larson is utensils and silverware go great with the dinnerware.', 0),
    (@Q2, N'Our most popular line, the Spring Flower China is sold out at most locations.', 0),
    (@Q2, N'Visit our store to check out our other beautiful products.', 0),
    (@Q2, N'They are dishwasher- and microwave-safe and we are confident that you will be using them for years to come.', 1);

    SELECT @Q2A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Larson is utensils and silverware go great with the dinnerware.';
    SELECT @Q2B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Our most popular line, the Spring Flower China is sold out at most locations.';
    SELECT @Q2C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Visit our store to check out our other beautiful products.';
    SELECT @Q2D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'They are dishwasher- and microwave-safe and we are confident that you will be using them for years to come.';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q2, @Q2A, 'A', 1),
    (@Q2, @Q2B, 'B', 2),
    (@Q2, @Q2C, 'C', 3),
    (@Q2, @Q2D, 'D', 4);

    /* =========================================================
       STEP 6: Answers cho Question 3
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q3, N'result in', 1),
    (@Q3, N'occur to', 0),
    (@Q3, N'ending at', 0),
    (@Q3, N'stop with', 0);

    SELECT @Q3A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'result in';
    SELECT @Q3B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'occur to';
    SELECT @Q3C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'ending at';
    SELECT @Q3D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'stop with';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q3, @Q3A, 'A', 1),
    (@Q3, @Q3B, 'B', 2),
    (@Q3, @Q3C, 'C', 3),
    (@Q3, @Q3D, 'D', 4);

    /* =========================================================
       STEP 7: Answers cho Question 4
       ========================================================= */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q4, N'ambitious', 0),
    (@Q4, N'combative', 0),
    (@Q4, N'aggressive', 1),
    (@Q4, N'complacent', 0);

    SELECT @Q4A = AnswerId FROM dbo.Answer WHERE QuestionId = @Q4 AND AnswerText = N'ambitious';
    SELECT @Q4B = AnswerId FROM dbo.Answer WHERE QuestionId = @Q4 AND AnswerText = N'combative';
    SELECT @Q4C = AnswerId FROM dbo.Answer WHERE QuestionId = @Q4 AND AnswerText = N'aggressive';
    SELECT @Q4D = AnswerId FROM dbo.Answer WHERE QuestionId = @Q4 AND AnswerText = N'complacent';

    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q4, @Q4A, 'A', 1),
    (@Q4, @Q4B, 'B', 2),
    (@Q4, @Q4C, 'C', 3),
    (@Q4, @Q4D, 'D', 4);

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;
    THROW;
END CATCH;
GO


-- ===== SEED TỐI THIỂU PART 7 ===== --
BEGIN TRAN;

BEGIN TRY
    DECLARE @EtsId INT;
    DECLARE @TestId INT;
    DECLARE @GroupId INT;

    DECLARE @Q1 INT, @Q2 INT, @Q3 INT;
    DECLARE @A1 INT, @A2 INT, @A3 INT, @A4 INT;
    DECLARE @B1 INT, @B2 INT, @B3 INT, @B4 INT;
    DECLARE @C1 INT, @C2 INT, @C3 INT, @C4 INT;

    /* ---- 2.1 Đảm bảo có AccountId = 1 để test attempt ---- */
    IF NOT EXISTS (SELECT 1 FROM dbo.Account WHERE AccountId = 1)
    BEGIN
        RAISERROR(N'Không tìm thấy AccountId = 1. Hãy tạo sẵn một tài khoản test trước khi chạy script này.', 16, 1);
    END

    /* ---- 2.2 Tạo EtsSet 2024 nếu chưa có ---- */
    IF NOT EXISTS (SELECT 1 FROM dbo.EtsSet WHERE [Year] = 2024)
    BEGIN
        INSERT INTO dbo.EtsSet([Year], Title)
        VALUES (2024, N'ETS 2024');
    END

    SELECT @EtsId = EtsId
    FROM dbo.EtsSet
    WHERE [Year] = 2024;

    /* ---- 2.3 Tạo TestNo = 99 để làm dữ liệu mẫu riêng ---- */
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Test
        WHERE EtsId = @EtsId
          AND TestNo = 99
    )
    BEGIN
        INSERT INTO dbo.Test(EtsId, TestNo, Title)
        VALUES (@EtsId, 99, N'ETS 2024 - Test 99 - Part 7 Sample');
    END

    SELECT @TestId = TestId
    FROM dbo.Test
    WHERE EtsId = @EtsId
      AND TestNo = 99;

    /* ---- 2.4 Nếu đã có group mẫu cũ cho test này thì xóa đi để seed sạch ---- */
    DELETE qo
    FROM dbo.QuestionOption qo
    INNER JOIN dbo.Question q ON qo.QuestionId = q.QuestionId
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 7
      AND g.OrderNo = 1;

    DELETE a
    FROM dbo.Answer a
    INNER JOIN dbo.Question q ON a.QuestionId = q.QuestionId
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 7
      AND g.OrderNo = 1;

    DELETE q
    FROM dbo.Question q
    INNER JOIN dbo.QuestionGroup g ON q.GroupId = g.GroupId
    WHERE g.TestId = @TestId
      AND g.PartId = 7
      AND g.OrderNo = 1;

    DELETE dbo.QuestionGroup
    WHERE TestId = @TestId
      AND PartId = 7
      AND OrderNo = 1;

    /* ---- 2.5 Tạo 1 group Part 7 ---- */
    INSERT INTO dbo.QuestionGroup
    (
        TestId,
        PartId,
        GroupType,
        AudioPath,
        ImagePath,
        PassageText,
        OrderNo
    )
    VALUES
    (
        @TestId,
        7,
        'PASSAGE',
        NULL,
        NULL,
        N'NOTICE TO EMPLOYEES

All staff members are invited to attend a customer service workshop on Friday, June 14, at 9:00 A.M. in Conference Room B. The workshop will be led by Ms. Linda Carson, a consultant with over fifteen years of industry experience.

Employees are asked to arrive at least ten minutes early. Printed materials will be distributed at the entrance. Refreshments will be provided during the mid-morning break.

If you have any questions, please contact the Human Resources Department before Thursday afternoon.',
        1
    );

    SET @GroupId = SCOPE_IDENTITY();

    /* ---- 2.6 Tạo 3 câu hỏi ---- */
    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        N'What is the purpose of the notice?',
        N'Thông báo mời nhân viên tham gia workshop về customer service.',
        1
    );
    SET @Q1 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        N'Who will lead the workshop?',
        N'Đoạn văn nêu rõ workshop sẽ do Ms. Linda Carson dẫn dắt.',
        2
    );
    SET @Q2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Question(GroupId, QuestionText, Explanation, OrderInGroup)
    VALUES
    (
        @GroupId,
        N'What are employees asked to do?',
        N'Nhân viên được yêu cầu đến sớm ít nhất mười phút.',
        3
    );
    SET @Q3 = SCOPE_IDENTITY();

    /* ---- 2.7 Đáp án câu 1 ---- */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q1, N'To announce a customer service workshop', 1),
    (@Q1, N'To introduce a new employee', 0),
    (@Q1, N'To cancel a meeting', 0),
    (@Q1, N'To request customer feedback', 0);

    SELECT @A1 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'To announce a customer service workshop';
    SELECT @A2 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'To introduce a new employee';
    SELECT @A3 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'To cancel a meeting';
    SELECT @A4 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q1 AND AnswerText = N'To request customer feedback';

    /* ---- 2.8 Đáp án câu 2 ---- */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q2, N'Ms. Linda Carson', 1),
    (@Q2, N'The Human Resources manager', 0),
    (@Q2, N'The company president', 0),
    (@Q2, N'A sales representative', 0);

    SELECT @B1 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'Ms. Linda Carson';
    SELECT @B2 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'The Human Resources manager';
    SELECT @B3 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'The company president';
    SELECT @B4 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q2 AND AnswerText = N'A sales representative';

    /* ---- 2.9 Đáp án câu 3 ---- */
    INSERT INTO dbo.Answer(QuestionId, AnswerText, IsCorrect)
    VALUES
    (@Q3, N'Arrive ten minutes early', 1),
    (@Q3, N'Bring their own refreshments', 0),
    (@Q3, N'Submit a report after the event', 0),
    (@Q3, N'Call the consultant directly', 0);

    SELECT @C1 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Arrive ten minutes early';
    SELECT @C2 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Bring their own refreshments';
    SELECT @C3 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Submit a report after the event';
    SELECT @C4 = AnswerId FROM dbo.Answer WHERE QuestionId = @Q3 AND AnswerText = N'Call the consultant directly';

    /* ---- 2.10 Seed QuestionOption gốc A/B/C/D ---- */
    INSERT INTO dbo.QuestionOption(QuestionId, AnswerId, OptionLabel, DisplayOrder)
    VALUES
    (@Q1, @A1, 'A', 1),
    (@Q1, @A2, 'B', 2),
    (@Q1, @A3, 'C', 3),
    (@Q1, @A4, 'D', 4),

    (@Q2, @B1, 'A', 1),
    (@Q2, @B2, 'B', 2),
    (@Q2, @B3, 'C', 3),
    (@Q2, @B4, 'D', 4),

    (@Q3, @C1, 'A', 1),
    (@Q3, @C2, 'B', 2),
    (@Q3, @C3, 'C', 3),
    (@Q3, @C4, 'D', 4);

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;
    THROW;
END CATCH;
GO
------

