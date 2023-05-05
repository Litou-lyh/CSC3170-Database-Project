/*
 * CSC3170 Group Project Dji database
 * Team Member:
 * Yihan Li     118010154
 * Zeyu Li      118010158
 * Yuxuan Liu   118010200
 * Yutao Qiu    118010247
 */


/*
	v2.1 update log:
    数据测试步骤：
    1. 运行此sql文件
    2. 由data import wizard 导入无人机，电池等数据到相应表中 （不勾选pid）
    3. 运行random_data.py补充其余数据
    


	(ver 1.4 by lzy) update log:
		1.Product.is_component (bool) changes into Product.type (Str)
		2.PK of OrderItem: item_id changes into order_id + item_number
		3.add Order.total_price
		(以上变更可讨论)

		a. py生成随机数据后直接import pymysql在py内写sql插入
		b. 对于Drone.pid外联无法插入数据的解释：
			设为FK后，只能插入被参考表内已有的值。
			这个直接插入Drone然后trigger的逻辑可能是错的...
			要不就不外联了
            
	(ver 1.5 by lyx  2021.4.24 11:50AM) update log
		1. 添加了几个真实的store数据
        2. 新增几个assumption
        3. 整理了一下代码顺序和结构，把所有关于插入数据的代码放到最后
        
    （ver 1.5b by lyh) update log: small changes
		new updates in v1.5b:
		1.数据插入方法：py生成随机数据后，直接复制到SQL文件里insert即可
		2.drone trigger中插入product数据的最后一个value改为‘drone’，与product.type对应
    
    (ver 1.6 by lyx) update log: index part
		新增index设置思考
        
	(ver 1.7 by lyh) update log:
	补全了依赖顺序的drop， 修改trigger bug， 现在可以跑通

	（ver 2.1 by lzy）:
    加入4个配件表与trigger，未测试

*/




/*
 * TODO:
 * A.查询内容：
 * -- 1. 各产品销量，销售额
 * -- 2. 各店总销售额
 * -- 3. 各销售员工业绩
 * -- 4. repair时查order日期，看有没有过保修期
 * -- 5. 查询产品生产厂家，维修更换
 * -- 6. 计算各产品（配件）损坏率
 * -- 7. 顾客年龄性别分析 (data mining?)
 *
 * B.数据插入方法：py生成随机数据后，直接复制到SQL文件里insert即可
 *
 */


/*
 * Important Assumptions of Database
 * 1. 不存在单独的维修点，所有维修点均在销售点内部（在Store表中使用canRepair属性标注该销售点是否支持维修服务）
 * 2. 每次维修的产品仅有一个，不支持多个pid的情况
 * 3. Staff仅分为三种：sale（销售），repair（维修）和factory（工厂工人）
 * 4. 任何一个员工只服务于一家商店或者工厂，不能同时服务多家
 */

/* 
 * 如何建立索引？
 * -------------
 * 索引大致分为两种：B树索引和hash索引
 * (!!! Important !!!) InnoDB引擎不支持显式设置hash索引，以下内容仅为理论分析
 * B树索引（数据结构：B树或B+树）		（InnoDB全部使用B+树作为数据结构）
 * 		优势：支持范围查找和组合索引，
 *		劣势：大多数情况下，查找效率低于hash索引
 * 		（B树相对于B+树的缺点：数据较大时树的高度会增加，从而增加查询时间复杂度，因为内存块的空间是固定的）
 * Hash索引（数据结构：哈希表）
 *		优势：hash值相同的可能性较低时，查询效率高于B树索引
 *		劣势：仅支持等值查找，不支持范围，大小查找，且不支持组合索引的单独使用（若将A+B设为hash索引，A，B必须一起出现，不能单独索引）
 * -----------------------------
 *
 * 1. 所有表的主键在创建时都被设置了默认的B+树主键索引，但实际上使用hash索引更好
 *	原因
 *		除了两个组合主键的表之外，剩下的主键全是id，不会出现范围查询以及hash值相同的情况，hash索引查询效率高于B+树
 * 2. 对于两个使用组合主键的表（orderitem + factoryProduct），只能使用B+树索引
 * 3. product name，factory name，customer name，staff name等姓名由于实际工作中需要经常用到，有必要建立B+树索引
 * 4. product price也会被经常用到，因为会有范围查询和hash值相同的情况，应设置B+树索引
 * 5. 所有外键因为要用来联结表，应设置索引（都是id，理论上使用hash索引更好）
 * 6. 索引不是建立得越多越好，建立的过多会加重存储负担，影响插入删除时的效率（因为要维护相应的数据结构）
 */



-- 创建数据库
CREATE DATABASE IF NOT EXISTS dji;
USE dji;

SHOW TABLES;

DROP TABLE IF EXISTS `Drone`;
DROP TABLE IF EXISTS `Battery`;
DROP TABLE IF EXISTS `ChargingHub`;
DROP TABLE IF EXISTS `Controller`;
DROP TABLE IF EXISTS `Propeller`;
DROP TABLE IF EXISTS `FactoryProduct`;
DROP TABLE IF EXISTS `Repair`;
DROP TABLE IF EXISTS `OrderItem`;
DROP TABLE IF EXISTS `Product`;
CREATE TABLE IF NOT EXISTS `Product`(
	`pid`		INT			NOT NULL	AUTO_INCREMENT,		-- 主键，唯一识别产品
    `name`		CHAR(100)	NOT NULL,						-- 产品名称
    `price`		FLOAT		NOT NULL,						-- 产品价格
--     `is_component`		BOOLEAN			NOT NULL,		    -- component or complete product -> inheritance
	`type`		CHAR(100)	NOT NULL,						-- 产品类型， 'drone', 'battery', 'controller', 'camera', 'gimbal'
    PRIMARY KEY (`pid`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";





-- 导入 drone_compact.csv without column 'drone_id'
DROP TABLE IF EXISTS `Drone`;
CREATE TABLE IF NOT EXISTS `Drone`(
    -- `drone_id`              INT         NOT NULL    AUTO_INCREMENT,     -- 主键，唯一识别drone
    `pid`                   INT         NOT NULL	AUTO_INCREMENT,		-- FOREIGN KEY from product
    `drone_name`            CHAR(100)   NOT NULL,                       -- the same as producr.name
    `drone_price`           FLOAT       NOT NULL,                       -- the same as product.price
    `take_off_weight`       FLOAT       NULL,                           -- 起飞高度
    `diagonal_length`       FLOAT       NULL,                           -- 对角轴距
    `max_flight_speed`      FLOAT       NULL,                           -- 最大飞行速度
    `max_flight_time`       FLOAT       NULL,                           -- 续航时间
    `max_wind_resistance`   FLOAT       NULL,                           -- 最大抗风
    `min_temperature`       FLOAT       NULL,                           -- 最低温度
    `max_temperature`       FLOAT       NULL,                           -- 最高温度
    -- PRIMARY KEY (`drone_id`),
    PRIMARY KEY(`pid`),
    FOREIGN KEY (`pid`) REFERENCES `Product`(`pid`)			
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

-- Trigger to add drone into product
DROP TRIGGER IF EXISTS drone_to_product;
DELIMITER //
CREATE TRIGGER drone_to_product 
BEFORE INSERT
ON drone FOR EACH ROW
BEGIN
	set new.pid = (select max(pid) from product) + 1;
    insert into product values(new.pid,new.drone_name,new.drone_price,'drone');
END//
DELIMITER ;

DROP TABLE IF EXISTS `Battery`;
CREATE TABLE IF NOT EXISTS `Battery`(
    `pid`                   	INT         NOT NULL	AUTO_INCREMENT,		-- FOREIGN KEY from product
    `battery_name`            			CHAR(100)   NOT NULL,                       -- the same as producr.name
	`battery_price`           			FLOAT       NOT NULL,                       -- the same as product.price
    `capacity`           		FLOAT       NULL,                       	-- 容量
    `voltage`       			FLOAT       NULL,                           -- 电压
    `Max_Charging_Voltage`  	FLOAT       NULL,                           -- 最大充电电压
    `Max_Charging_Power`   		FLOAT       NULL,                           -- 最大充点功率
    `type`       				CHAR(20)    NULL,                        	-- 类型
    `Energy`   					FLOAT       NULL,                           -- 能量
    `Min_Charging_Temp`  		FLOAT       NULL,                           -- 最低充电温度
    `Max_Charging_Temp`  		FLOAT       NULL,                           -- 最高充电温度
	`Weight`       				FLOAT       NULL,                           -- 重量

    PRIMARY KEY(`pid`),
    FOREIGN KEY (`pid`) REFERENCES `Product`(`pid`)			
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

-- Trigger to add battery into product
DROP TRIGGER IF EXISTS battery_to_product;
DELIMITER //
CREATE TRIGGER battery_to_product 
BEFORE INSERT
ON Battery FOR EACH ROW
BEGIN
	set new.pid = (select max(pid) from product) + 1;
    insert into product values(new.pid,new.battery_name,new.battery_price,'battery');
END//
DELIMITER ;

DROP TABLE IF EXISTS `Propeller`;
CREATE TABLE IF NOT EXISTS `Propeller`(
    `pid`       INT         NOT NULL	AUTO_INCREMENT,		-- FOREIGN KEY from product
    `Propeller_name`      CHAR(100)   NOT NULL,                       -- the same as producr.name
	`Propeller_price`     FLOAT       NOT NULL,                       -- the same as product.price
    `Diameter`  FLOAT       NULL,                       	-- 直径
    `Thread`    FLOAT       NULL,                           -- 轴
    `Weigh`  	FLOAT       NULL,                           -- 重量
    `type`      CHAR(20)       NULL,                        -- 类型

    PRIMARY KEY(`pid`),
    FOREIGN KEY (`pid`) REFERENCES `Product`(`pid`)			
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

-- Trigger to add Propeller into product
DROP TRIGGER IF EXISTS propeller_to_product;
DELIMITER //
CREATE TRIGGER propeller_to_product 
BEFORE INSERT
ON Propeller FOR EACH ROW
BEGIN
	set new.pid = (select max(pid) from product) + 1;
    insert into product values(new.pid,new.propeller_name,new.propeller_price,'propeller');
END//
DELIMITER ;

DROP TABLE IF EXISTS `ChargingHub`;
CREATE TABLE IF NOT EXISTS `ChargingHub`(
    `pid`                   	INT         NOT NULL	AUTO_INCREMENT,		-- FOREIGN KEY from product
    `ChargingHub_name`            			CHAR(100)   NOT NULL,                       -- the same as producr.name
	`ChargingHub_price`           			FLOAT       NOT NULL,                       -- the same as product.price
    `Whole_charging_time`       FLOAT       NULL,                       	-- 充电时间
    `Number_of_slots`       	FLOAT       NULL,                           -- 充电口数量
    `Max_Input_Current`  		FLOAT       NULL,                           -- 最大输入电流
    `Max_Input_Voltage`   		FLOAT       NULL,                           -- 最大输入电压
    `Min_Charging_Temp`  		FLOAT       NULL,                           -- 最低充电温度
    `Max_Charging_Temp`  		FLOAT       NULL,                           -- 最高充电温度
	`Weight`       				FLOAT       NULL,                           -- 重量

    PRIMARY KEY(`pid`),
    FOREIGN KEY (`pid`) REFERENCES `Product`(`pid`)			
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

-- Trigger to add battery into product
DROP TRIGGER IF EXISTS ChargingHub_to_product;
DELIMITER //
CREATE TRIGGER ChargingHub_to_product 
BEFORE INSERT
ON ChargingHub FOR EACH ROW
BEGIN
	set new.pid = (select max(pid) from product) + 1;
    insert into product values(new.pid,new.ChargingHub_name,new.ChargingHub_price,'ChargingHub');
END//
DELIMITER ;

DROP TABLE IF EXISTS `Controller`;
CREATE TABLE IF NOT EXISTS `Controller`(
    `pid`                   	INT         NOT NULL	AUTO_INCREMENT,		-- FOREIGN KEY from product
    `Controller_name`            			CHAR(100)   NOT NULL,                       -- the same as producr.name
	`Controller_price`           			FLOAT       NOT NULL,                       -- the same as product.price
    `Support_2.4G`          	BOOL        NULL,                       	-- 支持2.4G频率
    `Support_5.7G`       		BOOL        NULL,                           -- 支持5.7G频率
    `Max_FCC_Transm_Dist`		FLOAT       NULL,                           -- 最大FCC遥控距离
    `Max_CE_Transm_Dist`  		FLOAT       NULL,                           -- 最大CE遥控距离
    `Battery`       			CHAR(20)    NULL,                        	-- 电池类型
    `Operating Current`   		FLOAT       NULL,                           -- 工作电流
	`Operating Voltage`       	FLOAT       NULL,                           -- 工作电压
    `Min_Operating_Temp` 		FLOAT       NULL,                           -- 最低操作温度
    `Max_Operating_Temp` 		FLOAT       NULL,                           -- 最高操作温度

    PRIMARY KEY(`pid`),
    FOREIGN KEY (`pid`) REFERENCES `Product`(`pid`)			
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

-- Trigger to add Controller into product
DROP TRIGGER IF EXISTS controller_to_product;
DELIMITER //
CREATE TRIGGER controller_to_product 
BEFORE INSERT
ON Controller FOR EACH ROW
BEGIN
	set new.pid = (select max(pid) from product) + 1;
    insert into product values(new.pid,new.controller_name,new.controller_price,'controller');
END//
DELIMITER ;


DROP TABLE IF EXISTS `Repair`;
DROP TABLE IF EXISTS `Order`;
DROP TABLE IF EXISTS `Customer`;
CREATE TABLE IF NOT EXISTS `Customer`(
	`cust_id`	INT			NOT NULL	AUTO_INCREMENT,		-- 主键，唯一识别顾客
    `name`		CHAR(100)	NOT NULL,						-- 顾客名称
    `gender`	BOOLEAN		NULL,							-- 顾客性别（可为null）
    `age`		INT			NULL,							-- 顾客年龄（可为null）
    `address`	CHAR(255)	NULL,							-- 顾客地址（可为null）
    `telephone`	CHAR(30)	NULL,							-- 顾客手机号（可为null）
    PRIMARY KEY (`cust_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

-- Random customer data
insert into Customer values(null,'Yuxuan Liu', True, 21, 'CUHKSZ','133-3333-3333');
insert into Customer values(null,'Lou(ie)Susanna', 1, 43, '45°N6°E','1962106589909');
insert into Customer values(null,'DeQuinceyThera', 1, 48, '44°N178°E','1762996784308');
insert into Customer values(null,'BethuneWebb', 0, 17, '71°N9°E','1645997240996');
insert into Customer values(null,'VeromcaMacMillan', 0, 59, '69°N52°E','1540630472411');
insert into Customer values(null,'DeQuinceyThera', 1, 80, '89°N67°E','1995264713653');
insert into Customer values(null,'EvaAbel', 0, 72, '40°N40°E','1822296714348');
insert into Customer values(null,'KelvinDominic', 1, 16, '39°N90°E','1725188525406');
insert into Customer values(null,'BrunoPaul', 0, 70, '12°N146°E','1483358168955');
insert into Customer values(null,'SwiftSimona', 1, 34, '37°N124°E','1853659850788');
insert into Customer values(null,'HarrisonMartin', 1, 50, '19°N120°E','1877985443606');
insert into Customer values(null,'ParkerFrancis', 0, 52, '67°N73°E','1868084324150');
insert into Customer values(null,'YaleBeatrice', 1, 74, '56°N18°E','1561855434107');
insert into Customer values(null,'YaleBeatrice', 0, 57, '17°N166°E','1800196490709');
insert into Customer values(null,'DeweyKim', 0, 55, '35°N105°E','1607350865344');
insert into Customer values(null,'NickJay', 0, 37, '40°N106°E','1371547052830');
insert into Customer values(null,'PeggyEden', 1, 77, '36°N73°E','1532744102923');
insert into Customer values(null,'MurrayAdela', 1, 21, '39°N34°E','1443832200560');
insert into Customer values(null,'ParkerFrancis', 1, 51, '55°N10°E','1764749925125');
insert into Customer values(null,'JeamesMaxine', 1, 55, '22°N10°E','1727374141532');
insert into Customer values(null,'FeltonJim', 0, 58, '44°N179°E','1527882992965');


DROP TABLE IF EXISTS `SaleStaff`;
DROP TABLE IF EXISTS `RepairStaff`;
DROP TABLE IF EXISTS `FactoryStaff`;
DROP TABLE IF EXISTS `Staff`;
DROP TABLE IF EXISTS `Store`;
CREATE TABLE IF NOT EXISTS `Store`(
	`store_id`		INT			NOT NULL	AUTO_INCREMENT,			-- 主键，唯一识别商店
    `name`			CHAR(100)	NOT NULL,							-- 商店名称
--    `location`		CHAR(255)	NOT NULL,							-- 商店地址（是否需要细分为国家+地区+街道？）
	`country`       CHAR(100)	NOT NULL,							-- 工厂国家或地区
    `city`			CHAR(100)	NOT NULL,							-- 工厂城市
    `street`		CHAR(100)	NOT NULL,							-- 工厂街区
    `telephone`		CHAR(30)	NULL,								-- (待处理问题：一家门店可以有多个联系电话号码，如何处理，单独建表？) Assumption: only one   XD
    `open_hour`		CHAR(100)	NULL,								-- 商店开放时间
    `canRepair`		BOOLEAN		NOT NULL,							-- 该商店是否支持维修服务？
    `online`		BOOLEAN		NOT NULL,							-- online / offline    							and online no location? or to the warehouse location?
    PRIMARY KEY(`store_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

DROP TABLE IF EXISTS `OrderItem`;
DROP TABLE IF EXISTS `FactoryStaff`;
DROP TABLE IF EXISTS `Factory`;
CREATE TABLE IF NOT EXISTS `Factory`(
	`fact_id`		INT			NOT NULL	AUTO_INCREMENT,			-- 主键，唯一识别工厂
    `name`			CHAR(100)	NOT NULL,							-- 工厂名称
  --   `location`		CHAR(255)	NOT NULL,							-- 工厂地址（是否需要细分为国家+地区+街道？）
    `country`       CHAR(100)	NOT NULL,							-- 工厂国家或地区
    `city`			CHAR(100)	NOT NULL,							-- 工厂城市
    `street`		CHAR(100)	NOT NULL,							-- 工厂街区
    `telephone`		CHAR(30)	NULL,								-- (待处理问题：一家门店可以有多个联系电话号码，如何处理，单独建表？) Assumption: only one   XD
    `open_hour`		CHAR(100)	NULL,								-- 工厂开放时间
    PRIMARY KEY(`fact_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

/*
 * 为什么会有这个表？
 * 原因同orderitems，一个工厂可能生产多种产品（multi-value）
 * 通过factoryProduct可以记录每一家工厂生产的每一种产品，从而记录每种产品的产量。
 * 因此，主键为fact_id + item_number，item_number=0, 1, 2, ...
 */
DROP TABLE IF EXISTS `FactoryProduct`;
CREATE TABLE IF NOT EXISTS `FactoryProduct`(
-- 	`item_id`		INT			NOT NULL	AUTO_INCREMENT,			-- 主键，唯一识别制造项
	`fact_id`		INT			NOT NULL,							-- 主键之一：表示哪一个工厂
    `item_number`	INT			NOT NULL,							-- 主键之二：表示该工厂生产的第几件产品
    `pid`			INT			NOT NULL,							-- 产品id，外键
    `quantity`      FLOAT		NOT NULL,							-- 产品数量 / (以年为单位？)
    `item_pirce`	FLOAT		NOT NULL,							-- 项 价格（生产该产品的价格？）
    PRIMARY KEY(`fact_id`, `item_number`),
	FOREIGN KEY (`pid`) REFERENCES `Product`(`pid`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";


-- Staff继承设计：
-- Staff --> SaleStaff + RepairStaff + FactoryStaff
DROP TABLE IF EXISTS `SaleStaff`;
DROP TABLE IF EXISTS `RepairStaff`;
DROP TABLE IF EXISTS `FactoryStaff`;
DROP TABLE IF EXISTS `Staff`;
CREATE TABLE IF NOT EXISTS `Staff`(
	`staff_id`		INT			NOT NULL	AUTO_INCREMENT,			-- 主键，唯一识别staff
    `name`			CHAR(100)	NOT NULL,							-- the name of the staff
    `designation`	CHAR(20)		NOT NULL, 						-- sale / repair / Factory								Assumption: only three categories
    `salary`		FLOAT		NOT NULL,							-- salary per month
    `joined_date`	DATE		NOT NULL,							-- the date the staff hired
    -- ...
    PRIMARY KEY(`staff_id`)
    -- FOREIGN KEY(`store_id`) 			REFERENCES `Store`(`store_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";


DROP TABLE IF EXISTS `SaleStaff`;
CREATE TABLE IF NOT EXISTS `SaleStaff`(
	`staff_id`			INT			NOT NULL,						-- 主键，外键，唯一识别staff
    `name`				CHAR(100)	NOT NULL,						-- the name of the staff
    `designation`	CHAR(20)		NOT NULL, 						-- sale / repair / Factory	
	`salary`			FLOAT		NOT NULL,						-- salary per month
    `joined_date`		DATE		NOT NULL,						-- the date the staff hired
    
    `store_id`			INT			NOT NULL,						-- 外键，唯一识别store
    `sales_revenue`		FLOAT		NOT NULL,						-- 销售额

    PRIMARY KEY (`staff_id`),
    FOREIGN KEY(`staff_id`) 			REFERENCES `Staff`(`staff_id`),
	FOREIGN KEY(`store_id`) 			REFERENCES `Store`(`store_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";


-- trigger 可以做到插入各种staff时 Staff表里也自动插入，但需要Salestaff等specification表加入冗余的列，可以先加数据，再去掉

DROP TRIGGER IF EXISTS sale_staff;
DELIMITER //
CREATE TRIGGER sale_staff
BEFORE INSERT
ON SaleStaff FOR EACH ROW
BEGIN
	set new.staff_id = (select max(staff_id) from Staff) + 1;
    insert into Staff values(new.staff_id, new.name,'sale', new.salary, new.joined_date);
END//
DELIMITER ;


DROP TABLE IF EXISTS `RepairStaff`;
CREATE TABLE IF NOT EXISTS `RepairStaff`(
	`staff_id`			INT			NOT NULL,		-- 主键，唯一识别staff
    `name`			CHAR(100)	NOT NULL,							-- the name of the staff
    `designation`	CHAR(20)		NOT NULL, 						-- sale / repair / Factory	
    `salary`		FLOAT		NOT NULL,							-- salary per month
    `joined_date`	DATE		NOT NULL,							-- the date the staff hired    
    
	`store_id`			INT			NOT NULL,		-- 外键，唯一识别store
	`repair_quantity`	FLOAT		NOT NULL,		-- 维修额
    PRIMARY KEY (`staff_id`),
    FOREIGN KEY(`staff_id`) 			REFERENCES `Staff`(`staff_id`),
	FOREIGN KEY(`store_id`) 			REFERENCES `Store`(`store_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

DROP TRIGGER IF EXISTS repair_staff;
DELIMITER //
CREATE TRIGGER repair_staff
BEFORE INSERT
ON RepairStaff FOR EACH ROW
BEGIN
	set new.staff_id = (select max(staff_id) from Staff) + 1;
    insert into Staff values(new.staff_id, new.name,'repair', new.salary, new.joined_date);
END//
DELIMITER ;


DROP TABLE IF EXISTS `FactoryStaff`;
CREATE TABLE IF NOT EXISTS `FactoryStaff`(
	`staff_id`			INT			NOT NULL,		-- 主键，唯一识别staff
	`name`			CHAR(100)	NOT NULL,							-- the name of the staff
    `designation`	CHAR(20)		NOT NULL, 						-- sale / repair / Factory	
    `salary`		FLOAT		NOT NULL,							-- salary per month
    `joined_date`	DATE		NOT NULL,							-- the date the staff hired    
    
	`fact_id`			INT			NOT NULL,		-- 外键，唯一识别factory
    `manu_quantity`		FLOAT		NOT NULL,		-- 制造额

    PRIMARY KEY (`staff_id`),
    FOREIGN KEY(`staff_id`) 			REFERENCES `Staff`(`staff_id`),
	FOREIGN KEY(`fact_id`) 				REFERENCES `Factory`(`fact_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

DROP TRIGGER IF EXISTS fact_staff;
DELIMITER //
CREATE TRIGGER fact_staff
BEFORE INSERT
ON `FactoryStaff` FOR EACH ROW
BEGIN
	set new.`staff_id` = (select max(`staff_id`) from `Staff`) + 1;
    insert into `Staff` values(new.`staff_id`, new.name,'factory', new.`salary`, new.`joined_date`);
END//
DELIMITER ;




DROP TABLE IF EXISTS `Order`;
CREATE TABLE IF NOT EXISTS `Order`(
	`order_id`			INT			NOT NULL	AUTO_INCREMENT,		-- 主键，唯一识别订单
    `time`				DATETIME	NOT NULL,						-- 订单生成的时间
    `amount`			FLOAT		NOT NULL,						-- 订单金额
    `payment_method` 	CHAR(20)	NOT NULL,						-- 付款方式
    `discount`			FLOAT		NULL,							-- 订单折扣（可为null） 
    `total_price`		FLOAT		NOT NULL,						-- 订单总价格
    `deliver_address`	CHAR(100)	NULL,							-- 订单商品寄送地址（可为null）
    `cust_id`			INT			NOT NULL,						-- 外键，连接顾客表
    `staff_id`			INT			NULL,							-- 外键，连接员工表，哪位（营销）员工负责本次订单
    `store_id`			INT			NULL,							-- 外键，连接商店表，该订单发生在哪家商店
    
    PRIMARY KEY (`order_id`),
    FOREIGN KEY (`cust_id`) REFERENCES `Customer`(`cust_id`),
    FOREIGN KEY (`staff_id`) REFERENCES `Staff`(`staff_id`) ,
    FOREIGN KEY (`store_id`) REFERENCES `Store`(`store_id`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";

DROP TABLE IF EXISTS `OrderItem`;
CREATE TABLE IF NOT EXISTS `OrderItem`(
-- 	`item_id`			INT			NOT NULL	AUTO_INCREMENT,		-- 主键，唯一识别订单项目-- 
	`order_id`			INT			NOT NULL,						-- 主键1，连接订单
    `item_number`		INT			NOT NULL,						-- 主键2：表示订单的第几件产品
    `pid`				INT			NOT NULL,						-- 外键，连接产品
    -- (!!! Important !!!) 此处orderitems需要外联工厂表，不然我们无法知道每一个特定的产品生产自哪一个工厂
	`fact_id`			INT			NOT NULL,						-- 外键，连接工厂 
    `amount`			FLOAT		NOT NULL,						-- 数量
    `item_price`		FLOAT		NULL,							-- 项目价格
    
    PRIMARY KEY (`order_id`, `item_number`),
    FOREIGN KEY (`fact_id`) REFERENCES `Factory`(`fact_id`),
    FOREIGN KEY (`pid`) REFERENCES `Product`(`pid`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";


DROP TABLE IF EXISTS `Repair`;
CREATE TABLE IF NOT EXISTS `Repair`(
	`repair_id`			INT			NOT NULL	AUTO_INCREMENT,		-- 主键，唯一识别维修单
    `order_id`			INT			NOT NULL,						-- 外键，订单号
    `pid`				INT			NOT NULL,						-- 外键，产品id
	`cust_id`			INT			NOT NULL,						-- 外键，连接顾客表
    `staff_id`			INT			NULL,							-- 外键，连接员工表，哪位（维修）员工将维修
    `store_id`			INT			NULL,							-- 外键，连接商店表，将在那家店维修
    `time`				DATETIME	NOT NULL,						-- 维修单生成的时间
	`repair_component`	INT			NOT NULL,						-- pid 维修配件的产品id  Assumption: 一单一部件			Q: -> product.pid?
    `component_price`	FLOAT		NOT NULL,						-- 配件价格								 				Q: -> product.price
    `service_price`		FLOAT		NOT NULL,						-- 服务费
    `payment_method` 	CHAR(10)	NOT NULL,						-- 付款方式
    `discount`			FLOAT		NULL,							-- 订单折扣（可为null） 
    `deliver_address`	CHAR(10)	NULL,							-- 订单商品寄送地址（可为null）
    
    PRIMARY KEY (`repair_id`),
    FOREIGN KEY (`order_id`) 			REFERENCES `Order`(`order_id`),
    FOREIGN KEY (`pid`) 				REFERENCES `Product`(`pid`),
	FOREIGN KEY (`staff_id`) 			REFERENCES `Staff`(`staff_id`) ,
    FOREIGN KEY (`store_id`) 			REFERENCES `Store`(`store_id`),
    FOREIGN KEY (`repair_component`) 	REFERENCES `Product`(`pid`)
)ENGINE=InnoDB DEFAULT CHARSET="utf8mb4";








/* ----------------
 * !!! 插入数据 !!!
 * ---------------- */
INSERT INTO store (
	-- store_id
	`name`,	
	`country`,
    `city`,
    `street`,				
    `telephone`,
    `open_hour`,					
    `canRepair`,							
    `online`
)
VALUES
("DJI大疆深圳欢乐海岸旗舰店", "中国", "深圳", "南山区白石路8号欢乐海岸旅游信息中心", "0755-86665246", "周日至周四：10:00 - 22:00 周五至周六：10:00 - 22:30", true, false),
("深圳卓悦中心授权高级体验店", "中国", "深圳", "福田区深南大道2005号One Avenue卓悦中心B1层B158", "0755-88304158", "工作日10:00-22:00，节假日10:00-22:30", true, false),
("深圳万象天地授权高级体验店", "中国", "深圳", "南山区科技园万象天地商城L5-SL520", "0755-26830882", "10:00-22:30", true, false),
("广州西城都荟授权高级体验店", "中国", "广州", "荔湾区黄沙大道8号西城都荟1楼175号-176号铺", "18922179674", "10:00-22:00", true, false),
("深圳华强北授权体验店", "中国", "深圳", "福田区华强北路3010号万商电器城1层", "0755-83997769", "周一至周五：9:30 - 21:30 周六、周日：9:30 - 22:00", true, false);

SELECT * FROM store;
insert into Staff values(1, 'Hei Yin','sale', 6000, '2018-08-03');


-- query: find a customer
CREATE INDEX cust_name_index ON customer(name);
DROP INDEX cust_name_index ON customer; 
select customer.name									-- 0.016s with index on name / 0.766s+  without index
from customer
where customer.name = 'I.Hobart'
group by customer.name;


-- query the customer who have more than 7 orders
select cust_id, count(`order`.cust_id) as order_num								-- 0.078s+
from `order`
group by `order`.cust_id
having count(`order`.cust_id) > 7
order by order_num;

-- query customers who bought more than 18000 rmb
create view v as select `order`.cust_id, sum(`order`.total_price) as total
	from `order` group by `order`.cust_id
	having total > 18000;
    
select v.cust_id,customer.name, v.total				-- 41.406s+
from v natural join `customer`
-- where `customer`.cust_id = `order`.cust_id
order by `customer`.cust_id;	

-- query sale staffs of store 54 who joined after the year of 2015
select staff.staff_id, staff.name					-- 0.093s+
from staff natural join salestaff
where salestaff.store_id = 54 and staff.joined_date > '2015-01-01';


-- select count(*) from orderitem;

-- query orders containing drones	-- 6.250s+	-- unordered 0.39s+ / 5.656s fetch
select `order`.order_id, customer.cust_id, customer.name, drone.pid, drone.drone_name
from customer, `order`, orderItem, drone
where customer.cust_id = `order`.cust_id and `order`.order_id = orderItem.order_id and orderItem.pid = drone.pid
order by `order`.order_id;

-- drone sale numbers	-- 6.078s+
select drone.pid,drone.drone_name, count(*) as num
from customer, `order`, orderItem, drone
where customer.cust_id = `order`.cust_id and `order`.order_id = orderItem.order_id and orderItem.pid = drone.pid
group by drone.pid
order by num desc;

-- drone sales	-- 6.219s+
select drone.pid,drone.drone_name, count(*) as num,count(*) * drone.drone_price / 10000 as sale_10k
from customer, `order`, orderItem, drone
where customer.cust_id = `order`.cust_id and `order`.order_id = orderItem.order_id and orderItem.pid = drone.pid
group by drone.pid
order by sale_10k desc;

-- SET AUTOCOMMIT=0;
-- SET AUTOCOMMIT=1;