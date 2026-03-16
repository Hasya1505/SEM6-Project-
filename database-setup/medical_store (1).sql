-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Mar 16, 2026 at 06:09 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `medical_store`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_add_batch` (IN `p_product_id` INT, IN `p_batch_number` VARCHAR(50), IN `p_quantity` INT, IN `p_expiry_date` DATE, IN `p_cost_price` DECIMAL(10,2), IN `p_supplier_id` INT, IN `p_user_id` INT)   BEGIN
    DECLARE v_batch_id INT;
    
    -- Insert or update batch
    INSERT INTO product_batches (product_id, batch_number, quantity, expiry_date, cost_price, supplier_id)
    VALUES (p_product_id, p_batch_number, p_quantity, p_expiry_date, p_cost_price, p_supplier_id)
    ON DUPLICATE KEY UPDATE 
        quantity = quantity + p_quantity,
        expiry_date = p_expiry_date,
        cost_price = p_cost_price;
    
    SET v_batch_id = LAST_INSERT_ID();
    
    -- Record transaction
    INSERT INTO batch_transactions (batch_id, transaction_type, quantity_change, created_by)
    VALUES (v_batch_id, 'purchase', p_quantity, p_user_id);
    
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_sell_product` (IN `p_product_id` INT, IN `p_quantity` INT, IN `p_bill_id` INT, OUT `p_success` BOOLEAN, OUT `p_message` VARCHAR(255))   BEGIN
    DECLARE v_remaining INT DEFAULT p_quantity;
    DECLARE v_batch_id INT;
    DECLARE v_batch_qty INT;
    DECLARE v_qty_to_deduct INT;
    DECLARE v_price DECIMAL(10,2);
    DECLARE done INT DEFAULT FALSE;
    
    DECLARE batch_cursor CURSOR FOR
        SELECT id, quantity 
        FROM product_batches 
        WHERE product_id = p_product_id 
          AND quantity > 0
          AND (expiry_date IS NULL OR expiry_date > CURDATE())
        ORDER BY expiry_date ASC, quantity ASC  -- FIFO: First expiry, less stock
        FOR UPDATE;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- Get product price
    SELECT price INTO v_price FROM products WHERE id = p_product_id;
    
    START TRANSACTION;
    
    OPEN batch_cursor;
    
    read_loop: LOOP
        FETCH batch_cursor INTO v_batch_id, v_batch_qty;
        
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Calculate how much to deduct from this batch
        IF v_remaining <= v_batch_qty THEN
            SET v_qty_to_deduct = v_remaining;
        ELSE
            SET v_qty_to_deduct = v_batch_qty;
        END IF;
        
        -- Update batch quantity
        UPDATE product_batches 
        SET quantity = quantity - v_qty_to_deduct 
        WHERE id = v_batch_id;
        
        -- Record batch bill item
        INSERT INTO batch_bill_items (bill_id, batch_id, quantity, price_per_unit, total_amount)
        VALUES (p_bill_id, v_batch_id, v_qty_to_deduct, v_price, v_qty_to_deduct * v_price);
        
        -- Record transaction
        INSERT INTO batch_transactions (batch_id, transaction_type, quantity_change, reference_type, reference_id)
        VALUES (v_batch_id, 'sale', -v_qty_to_deduct, 'bill', p_bill_id);
        
        SET v_remaining = v_remaining - v_qty_to_deduct;
        
        IF v_remaining = 0 THEN
            LEAVE read_loop;
        END IF;
        
    END LOOP;
    
    CLOSE batch_cursor;
    
    -- Check if we fulfilled the order
    IF v_remaining > 0 THEN
        SET p_success = FALSE;
        SET p_message = CONCAT('Insufficient stock. Missing: ', v_remaining, ' units');
        ROLLBACK;
    ELSE
        SET p_success = TRUE;
        SET p_message = 'Sale completed successfully';
        COMMIT;
    END IF;
    
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `batch_bill_items`
--

CREATE TABLE `batch_bill_items` (
  `id` int(11) NOT NULL,
  `bill_id` int(11) NOT NULL,
  `batch_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL,
  `price_per_unit` decimal(10,2) NOT NULL,
  `total_amount` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `batch_transactions`
--

CREATE TABLE `batch_transactions` (
  `id` int(11) NOT NULL,
  `batch_id` int(11) NOT NULL,
  `transaction_type` enum('purchase','sale','return','adjustment','disposal') NOT NULL,
  `quantity_change` int(11) NOT NULL COMMENT 'Positive for additions, negative for reductions',
  `transaction_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `reference_type` varchar(20) DEFAULT NULL COMMENT 'bill, purchase_order, etc',
  `reference_id` int(11) DEFAULT NULL COMMENT 'ID of the related record',
  `notes` text DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `bills`
--

CREATE TABLE `bills` (
  `id` int(11) NOT NULL,
  `bill_number` varchar(50) NOT NULL,
  `customer_id` int(11) DEFAULT NULL,
  `customer_name` varchar(100) NOT NULL,
  `phone` varchar(15) DEFAULT NULL,
  `subtotal` decimal(10,2) NOT NULL DEFAULT 0.00,
  `gst` decimal(10,2) NOT NULL DEFAULT 0.00,
  `total_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `payment_method` enum('cash','upi') NOT NULL DEFAULT 'cash' COMMENT 'Payment method used',
  `payment_status` enum('pending','approved','completed') NOT NULL DEFAULT 'completed' COMMENT 'Payment approval status',
  `payment_approved_at` timestamp NULL DEFAULT NULL COMMENT 'When UPI payment was approved',
  `payment_approved_by` int(11) DEFAULT NULL COMMENT 'User who approved payment',
  `bill_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `created_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `bills`
--

INSERT INTO `bills` (`id`, `bill_number`, `customer_id`, `customer_name`, `phone`, `subtotal`, `gst`, `total_amount`, `payment_method`, `payment_status`, `payment_approved_at`, `payment_approved_by`, `bill_date`, `created_by`) VALUES
(1, 'INV-26-000', 34, 'Prisha Mehta', '9861949446', 5098.70, 611.84, 5710.54, 'upi', 'completed', NULL, NULL, '2026-01-17 04:29:31', 2),
(2, 'INV-26-001', NULL, 'Walk-in Customer', '0000000000', 1040.44, 124.85, 1165.29, 'upi', 'completed', NULL, NULL, '2026-01-27 07:27:56', 1),
(3, 'INV-26-002', NULL, 'Walk-in Customer', '0000000000', 5625.17, 675.02, 6300.19, 'upi', 'completed', NULL, NULL, '2026-01-13 02:49:55', 2),
(4, 'INV-26-003', NULL, 'Walk-in Customer', '0000000000', 3738.78, 448.65, 4187.43, 'upi', 'completed', NULL, NULL, '2026-03-04 08:30:48', 2),
(5, 'INV-26-004', 66, 'Ishaan Gajjar', '9833315291', 2237.20, 268.46, 2505.66, 'cash', 'completed', NULL, NULL, '2026-03-09 16:53:41', 2),
(6, 'INV-26-005', 61, 'Dhara Gajjar', '9885225280', 1799.98, 216.00, 2015.98, 'upi', 'completed', NULL, NULL, '2026-02-22 05:57:28', 1),
(7, 'INV-26-006', 30, 'Ishaan Mehta', '9851317736', 565.48, 67.86, 633.34, 'upi', 'completed', NULL, NULL, '2026-03-04 09:16:24', 1),
(8, 'INV-26-007', 34, 'Prisha Mehta', '9861949446', 2678.86, 321.46, 3000.32, 'cash', 'completed', NULL, NULL, '2026-03-05 10:02:03', 1),
(9, 'INV-26-008', 62, 'Ishaan Desai', '9849730460', 6391.41, 766.97, 7158.38, 'upi', 'completed', NULL, NULL, '2026-02-05 04:19:38', 2),
(10, 'INV-26-009', 20, 'Kabir Mehta', '9897563514', 1273.85, 152.86, 1426.71, 'upi', 'completed', NULL, NULL, '2026-02-05 06:53:11', 2),
(11, 'INV-26-010', 22, 'Jiya Gajjar', '9871550784', 8316.55, 997.99, 9314.54, 'upi', 'completed', NULL, NULL, '2026-01-13 07:25:24', 1),
(12, 'INV-26-011', 2, 'Prisha Patel', '9860065845', 5413.81, 649.66, 6063.47, 'cash', 'completed', NULL, NULL, '2026-02-03 06:13:53', 2),
(13, 'INV-26-012', 21, 'Naitik Shah', '9851391266', 592.98, 71.16, 664.14, 'upi', 'completed', NULL, NULL, '2026-01-05 02:50:24', 2),
(14, 'INV-26-013', 31, 'Jiya Shah', '9885454077', 2806.49, 336.78, 3143.27, 'cash', 'completed', NULL, NULL, '2026-01-17 07:28:59', 2),
(15, 'INV-26-014', 19, 'Ishaan Mehta', '9854976958', 3040.00, 364.80, 3404.80, 'upi', 'completed', NULL, NULL, '2026-03-15 15:09:49', 1),
(16, 'INV-26-015', 32, 'Kabir Shah', '9816699956', 4366.48, 523.98, 4890.46, 'upi', 'completed', NULL, NULL, '2026-03-13 16:21:10', 1),
(17, 'INV-26-016', 53, 'Jiya Shah', '9878436587', 1095.84, 131.50, 1227.34, 'cash', 'completed', NULL, NULL, '2026-03-03 13:41:23', 2),
(18, 'INV-26-017', 60, 'Ishaan Desai', '9885006126', 380.00, 45.60, 425.60, 'upi', 'completed', NULL, NULL, '2026-03-26 06:24:39', 2),
(19, 'INV-26-018', 60, 'Ishaan Desai', '9885006126', 5452.48, 654.30, 6106.78, 'upi', 'completed', NULL, NULL, '2026-03-19 18:21:08', 2),
(20, 'INV-26-019', NULL, 'Walk-in Customer', '0000000000', 2183.24, 261.99, 2445.23, 'upi', 'completed', NULL, NULL, '2026-03-07 02:40:35', 2),
(21, 'INV-26-020', 76, 'Ishaan Trivedi', '9893393032', 2393.48, 287.22, 2680.70, 'cash', 'completed', NULL, NULL, '2026-02-06 02:36:32', 2),
(22, 'INV-26-021', 59, 'Dhara Desai', '9814883550', 1656.00, 198.72, 1854.72, 'upi', 'completed', NULL, NULL, '2026-03-12 18:26:31', 2),
(23, 'INV-26-022', 10, 'Meera Trivedi', '9839230771', 2843.79, 341.25, 3185.04, 'upi', 'completed', NULL, NULL, '2026-02-03 03:35:17', 2),
(24, 'INV-26-023', 56, 'Meera Choksi', '9853915278', 6185.64, 742.28, 6927.92, 'upi', 'completed', NULL, NULL, '2026-01-13 08:15:04', 2),
(25, 'INV-26-024', 72, 'Ishaan Patel', '9899356059', 2017.60, 242.11, 2259.71, 'cash', 'completed', NULL, NULL, '2026-01-12 14:58:27', 2),
(26, 'INV-26-025', 31, 'Jiya Shah', '9885454077', 3049.32, 365.92, 3415.24, 'cash', 'completed', NULL, NULL, '2026-02-23 03:07:51', 2),
(27, 'INV-26-026', 40, 'Kabir Desai', '9878644126', 527.58, 63.31, 590.89, 'upi', 'completed', NULL, NULL, '2026-01-15 03:07:43', 1),
(28, 'INV-26-027', 76, 'Ishaan Trivedi', '9893393032', 360.00, 43.20, 403.20, 'upi', 'completed', NULL, NULL, '2026-01-11 14:31:45', 2),
(29, 'INV-26-028', 33, 'Dhara Trivedi', '9878317808', 2695.70, 323.48, 3019.18, 'upi', 'completed', NULL, NULL, '2026-02-10 05:56:34', 2),
(30, 'INV-26-029', NULL, 'Walk-in Customer', '0000000000', 1844.49, 221.34, 2065.83, 'upi', 'completed', NULL, NULL, '2026-02-05 04:22:14', 2),
(31, 'INV-26-030', NULL, 'Walk-in Customer', '0000000000', 2094.43, 251.33, 2345.76, 'cash', 'completed', NULL, NULL, '2026-03-06 11:27:28', 2),
(32, 'INV-26-031', 67, 'Meera Gajjar', '9825927844', 1440.80, 172.90, 1613.70, 'cash', 'completed', NULL, NULL, '2026-03-12 06:44:34', 2),
(33, 'INV-26-032', 19, 'Ishaan Mehta', '9854976958', 1337.05, 160.45, 1497.50, 'upi', 'completed', NULL, NULL, '2026-03-11 03:03:48', 2),
(34, 'INV-26-033', NULL, 'Walk-in Customer', '0000000000', 1588.38, 190.61, 1778.99, 'cash', 'completed', NULL, NULL, '2026-01-10 02:35:26', 1),
(35, 'INV-26-034', 60, 'Ishaan Desai', '9885006126', 2033.24, 243.99, 2277.23, 'cash', 'completed', NULL, NULL, '2026-03-28 03:02:16', 2),
(36, 'INV-26-035', NULL, 'Walk-in Customer', '0000000000', 138.44, 16.61, 155.05, 'upi', 'completed', NULL, NULL, '2026-03-11 17:55:24', 2),
(37, 'INV-26-036', 68, 'Naitik Shah', '9812753144', 4462.75, 535.53, 4998.28, 'upi', 'completed', NULL, NULL, '2026-01-10 06:21:07', 1),
(38, 'INV-26-037', NULL, 'Walk-in Customer', '0000000000', 116.93, 14.03, 130.96, 'upi', 'completed', NULL, NULL, '2026-01-05 14:21:06', 2),
(39, 'INV-26-038', 50, 'Ishaan Patel', '9897904868', 4602.30, 552.28, 5154.58, 'upi', 'completed', NULL, NULL, '2026-01-26 17:33:32', 1),
(40, 'INV-26-039', 42, 'Prisha Patel', '9850381049', 2374.75, 284.97, 2659.72, 'upi', 'completed', NULL, NULL, '2026-02-01 15:55:28', 2),
(41, 'INV-26-040', 74, 'Meera Desai', '9840010510', 2871.56, 344.59, 3216.15, 'upi', 'completed', NULL, NULL, '2026-02-14 08:00:57', 1),
(42, 'INV-26-041', NULL, 'Walk-in Customer', '0000000000', 1149.03, 137.88, 1286.91, 'upi', 'completed', NULL, NULL, '2026-03-25 12:40:40', 1),
(43, 'INV-26-042', 9, 'Dhara Trivedi', '9831981506', 2589.55, 310.75, 2900.30, 'cash', 'completed', NULL, NULL, '2026-02-14 09:46:14', 2),
(44, 'INV-26-043', 26, 'Aarav Mehta', '9872165217', 3117.36, 374.08, 3491.44, 'upi', 'completed', NULL, NULL, '2026-01-03 03:50:14', 2),
(45, 'INV-26-044', NULL, 'Walk-in Customer', '0000000000', 3058.81, 367.06, 3425.87, 'cash', 'completed', NULL, NULL, '2026-02-02 05:06:47', 1),
(46, 'INV-26-045', 77, 'Aarav Shah', '9861426323', 545.47, 65.46, 610.93, 'cash', 'completed', NULL, NULL, '2026-02-21 13:42:31', 2),
(47, 'INV-26-046', 2, 'Prisha Patel', '9860065845', 250.00, 30.00, 280.00, 'upi', 'completed', NULL, NULL, '2026-01-17 03:31:15', 1),
(48, 'INV-26-047', 75, 'Ishaan Desai', '9839620368', 1724.02, 206.88, 1930.90, 'upi', 'completed', NULL, NULL, '2026-01-06 12:02:32', 2),
(49, 'INV-26-048', 41, 'Meera Desai', '9850755013', 1062.63, 127.52, 1190.15, 'cash', 'completed', NULL, NULL, '2026-01-22 06:20:29', 1),
(50, 'INV-26-049', 71, 'Kabir Mehta', '9846750764', 3183.85, 382.06, 3565.91, 'cash', 'completed', NULL, NULL, '2026-01-08 02:30:47', 2),
(51, 'INV-26-050', 63, 'Jiya Trivedi', '9882154166', 240.00, 28.80, 268.80, 'cash', 'completed', NULL, NULL, '2026-03-09 12:58:41', 2),
(52, 'INV-26-051', 46, 'Prisha Trivedi', '9869619864', 5434.72, 652.17, 6086.89, 'cash', 'completed', NULL, NULL, '2026-01-02 08:17:04', 2),
(53, 'INV-26-052', 1, 'Meera Shah', '9867155219', 5762.49, 691.50, 6453.99, 'upi', 'completed', NULL, NULL, '2026-03-28 06:03:05', 2),
(54, 'INV-26-053', 74, 'Meera Desai', '9840010510', 3193.52, 383.22, 3576.74, 'cash', 'completed', NULL, NULL, '2026-01-28 11:28:05', 1),
(55, 'INV-26-054', NULL, 'Walk-in Customer', '0000000000', 2443.72, 293.25, 2736.97, 'upi', 'completed', NULL, NULL, '2026-03-19 13:49:30', 1),
(56, 'INV-26-055', NULL, 'Walk-in Customer', '0000000000', 1081.72, 129.81, 1211.53, 'cash', 'completed', NULL, NULL, '2026-01-19 11:20:20', 2),
(57, 'INV-26-056', 27, 'Aarav Mehta', '9815711822', 534.82, 64.18, 599.00, 'upi', 'completed', NULL, NULL, '2026-02-24 10:10:49', 2),
(58, 'INV-26-057', 34, 'Prisha Mehta', '9861949446', 3875.02, 465.00, 4340.02, 'cash', 'completed', NULL, NULL, '2026-03-19 18:25:55', 2),
(59, 'INV-26-058', 58, 'Prisha Gajjar', '9883272001', 5119.57, 614.35, 5733.92, 'cash', 'completed', NULL, NULL, '2026-01-05 07:01:04', 1),
(60, 'INV-26-059', 52, 'Meera Shah', '9831346968', 613.44, 73.61, 687.05, 'cash', 'completed', NULL, NULL, '2026-02-20 04:53:07', 2),
(61, 'INV-26-060', NULL, 'Walk-in Customer', '0000000000', 170.10, 20.41, 190.51, 'cash', 'completed', NULL, NULL, '2026-02-15 03:20:52', 2),
(62, 'INV-26-061', NULL, 'Walk-in Customer', '0000000000', 3664.29, 439.71, 4104.00, 'cash', 'completed', NULL, NULL, '2026-01-25 12:49:44', 1),
(63, 'INV-26-062', 27, 'Aarav Mehta', '9815711822', 2344.60, 281.35, 2625.95, 'cash', 'completed', NULL, NULL, '2026-03-02 07:53:32', 2),
(64, 'INV-26-063', NULL, 'Walk-in Customer', '0000000000', 76.76, 9.21, 85.97, 'cash', 'completed', NULL, NULL, '2026-02-05 15:24:45', 1),
(65, 'INV-26-064', 21, 'Naitik Shah', '9851391266', 3426.94, 411.23, 3838.17, 'cash', 'completed', NULL, NULL, '2026-02-10 11:49:16', 1),
(66, 'INV-26-065', 30, 'Ishaan Mehta', '9851317736', 3529.42, 423.53, 3952.95, 'cash', 'completed', NULL, NULL, '2026-01-13 12:33:49', 2),
(67, 'INV-26-066', 42, 'Prisha Patel', '9850381049', 2925.51, 351.06, 3276.57, 'upi', 'completed', NULL, NULL, '2026-02-09 16:22:36', 2),
(68, 'INV-26-067', 76, 'Ishaan Trivedi', '9893393032', 1720.87, 206.50, 1927.37, 'upi', 'completed', NULL, NULL, '2026-01-20 13:37:46', 1),
(69, 'INV-26-068', 74, 'Meera Desai', '9840010510', 5309.93, 637.19, 5947.12, 'upi', 'completed', NULL, NULL, '2026-02-15 13:04:00', 2),
(70, 'INV-26-069', 45, 'Aarav Shah', '9830960343', 243.87, 29.26, 273.13, 'cash', 'completed', NULL, NULL, '2026-02-17 12:49:38', 1),
(71, 'INV-26-070', 52, 'Meera Shah', '9831346968', 2604.11, 312.49, 2916.60, 'cash', 'completed', NULL, NULL, '2026-03-14 14:46:10', 2),
(72, 'INV-26-071', NULL, 'Walk-in Customer', '0000000000', 2809.25, 337.11, 3146.36, 'upi', 'completed', NULL, NULL, '2026-01-19 17:34:44', 2),
(73, 'INV-26-072', NULL, 'Walk-in Customer', '0000000000', 145.00, 17.40, 162.40, 'cash', 'completed', NULL, NULL, '2026-01-13 14:34:40', 2),
(74, 'INV-26-073', 1, 'Meera Shah', '9867155219', 3477.34, 417.28, 3894.62, 'upi', 'completed', NULL, NULL, '2026-02-11 16:07:18', 2),
(75, 'INV-26-074', 32, 'Kabir Shah', '9816699956', 3685.66, 442.28, 4127.94, 'upi', 'completed', NULL, NULL, '2026-02-02 14:16:09', 2),
(76, 'INV-26-075', 3, 'Meera Mehta', '9891994349', 769.64, 92.36, 862.00, 'cash', 'completed', NULL, NULL, '2026-01-02 03:35:03', 2),
(77, 'INV-26-076', 10, 'Meera Trivedi', '9839230771', 1483.56, 178.03, 1661.59, 'upi', 'completed', NULL, NULL, '2026-03-12 03:48:26', 1),
(78, 'INV-26-077', NULL, 'Walk-in Customer', '0000000000', 3026.46, 363.18, 3389.64, 'cash', 'completed', NULL, NULL, '2026-03-12 05:31:46', 2),
(79, 'INV-26-078', 8, 'Kabir Desai', '9844412104', 1269.21, 152.31, 1421.52, 'upi', 'completed', NULL, NULL, '2026-03-05 06:51:33', 2),
(80, 'INV-26-079', 70, 'Dhara Patel', '9865746473', 1922.55, 230.71, 2153.26, 'upi', 'completed', NULL, NULL, '2026-01-16 06:31:57', 1),
(81, 'INV-26-080', 34, 'Prisha Mehta', '9861949446', 354.21, 42.51, 396.72, 'cash', 'completed', NULL, NULL, '2026-01-28 09:41:58', 1),
(82, 'INV-26-081', 35, 'Aarav Desai', '9824037198', 1108.68, 133.04, 1241.72, 'cash', 'completed', NULL, NULL, '2026-02-09 06:58:14', 1),
(83, 'INV-26-082', 40, 'Kabir Desai', '9878644126', 25.00, 3.00, 28.00, 'cash', 'completed', NULL, NULL, '2026-01-08 07:37:59', 2),
(84, 'INV-26-083', 43, 'Prisha Mehta', '9817249269', 2366.65, 284.00, 2650.65, 'cash', 'completed', NULL, NULL, '2026-02-28 13:27:07', 2),
(85, 'INV-26-084', 47, 'Ishaan Desai', '9837902560', 4316.42, 517.97, 4834.39, 'upi', 'completed', NULL, NULL, '2026-01-23 06:25:02', 1),
(86, 'INV-26-085', 14, 'Meera Choksi', '9819896506', 3950.44, 474.05, 4424.49, 'upi', 'completed', NULL, NULL, '2026-03-20 03:29:24', 1),
(87, 'INV-26-086', 22, 'Jiya Gajjar', '9871550784', 5582.69, 669.92, 6252.61, 'cash', 'completed', NULL, NULL, '2026-01-15 13:31:59', 2),
(88, 'INV-26-087', 51, 'Jiya Mehta', '9857784537', 3951.53, 474.18, 4425.71, 'upi', 'completed', NULL, NULL, '2026-03-17 18:04:23', 2),
(89, 'INV-26-088', NULL, 'Walk-in Customer', '0000000000', 5801.48, 696.18, 6497.66, 'cash', 'completed', NULL, NULL, '2026-03-24 08:58:55', 2),
(90, 'INV-26-089', 60, 'Ishaan Desai', '9885006126', 3107.39, 372.89, 3480.28, 'upi', 'completed', NULL, NULL, '2026-03-06 03:06:52', 1),
(91, 'INV-26-090', 53, 'Jiya Shah', '9878436587', 3528.90, 423.47, 3952.37, 'cash', 'completed', NULL, NULL, '2026-01-03 10:25:29', 1),
(92, 'INV-26-091', 39, 'Prisha Choksi', '9822470141', 5422.12, 650.65, 6072.77, 'upi', 'completed', NULL, NULL, '2026-03-18 07:09:03', 2),
(93, 'INV-26-092', NULL, 'Walk-in Customer', '0000000000', 3650.50, 438.06, 4088.56, 'cash', 'completed', NULL, NULL, '2026-02-02 03:32:55', 2),
(94, 'INV-26-093', NULL, 'Walk-in Customer', '0000000000', 2139.02, 256.68, 2395.70, 'cash', 'completed', NULL, NULL, '2026-02-28 02:54:43', 1),
(95, 'INV-26-094', 60, 'Ishaan Desai', '9885006126', 3523.52, 422.82, 3946.34, 'cash', 'completed', NULL, NULL, '2026-02-07 16:27:57', 1),
(96, 'INV-26-095', 56, 'Meera Choksi', '9853915278', 793.92, 95.27, 889.19, 'cash', 'completed', NULL, NULL, '2026-01-25 11:48:56', 1),
(97, 'INV-26-096', 70, 'Dhara Patel', '9865746473', 1538.31, 184.60, 1722.91, 'upi', 'completed', NULL, NULL, '2026-01-17 14:21:41', 2),
(98, 'INV-26-097', 57, 'Kabir Choksi', '9869916500', 708.42, 85.01, 793.43, 'cash', 'completed', NULL, NULL, '2026-02-08 13:34:51', 2),
(99, 'INV-26-098', 66, 'Ishaan Gajjar', '9833315291', 3223.45, 386.81, 3610.26, 'upi', 'completed', NULL, NULL, '2026-02-12 14:47:23', 2),
(100, 'INV-26-099', 3, 'Meera Mehta', '9891994349', 5286.15, 634.34, 5920.49, 'upi', 'completed', NULL, NULL, '2026-01-01 07:12:40', 1),
(101, 'INV-20260314172547', 79, 'HASYA  PATEL', '7862023272', 243.87, 29.26, 273.13, 'upi', 'completed', '2026-03-14 11:57:10', 1, '2026-03-14 11:57:10', 1),
(102, 'INV-20260315120754', 79, 'HASYA  PATEL', '7862023272', 5323.05, 638.77, 5961.82, 'upi', 'completed', '2026-03-15 06:37:59', 1, '2026-03-15 06:37:59', 1);

-- --------------------------------------------------------

--
-- Table structure for table `bill_items`
--

CREATE TABLE `bill_items` (
  `id` int(11) NOT NULL,
  `bill_id` int(11) NOT NULL,
  `product_id` int(11) DEFAULT NULL,
  `medicine_name` varchar(200) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `quantity` int(11) NOT NULL,
  `total_amount` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `bill_items`
--

INSERT INTO `bill_items` (`id`, `bill_id`, `product_id`, `medicine_name`, `price`, `quantity`, `total_amount`) VALUES
(1, 1, 94, 'Metformin Syrup', 763.84, 4, 3055.36),
(2, 1, 78, 'Calcium 10mg', 257.83, 2, 515.66),
(3, 1, 94, 'Metformin Syrup', 763.84, 2, 1527.68),
(4, 2, 43, 'Pantoprazole 500mg', 38.38, 3, 115.14),
(5, 2, 49, 'Azithromycin 500mg', 185.06, 5, 925.30),
(6, 3, 81, 'Vitamin D3 500mg', 542.83, 4, 2171.32),
(7, 3, 12, 'Multivitamin Capsules', 120.00, 4, 480.00),
(8, 3, 16, 'Azithromycin 10mg', 594.77, 5, 2973.85),
(9, 4, 74, 'Azithromycin 10mg', 697.53, 2, 1395.06),
(10, 4, 100, 'Vitamin D3 Syrup', 781.24, 3, 2343.72),
(11, 5, 56, 'Pantoprazole 10mg', 559.30, 4, 2237.20),
(12, 6, 51, 'Pantoprazole 250mg', 95.27, 4, 381.08),
(13, 6, 68, 'Omeprazole 500mg', 159.65, 4, 638.60),
(14, 6, 98, 'Calcium Syrup', 260.10, 3, 780.30),
(15, 7, 92, 'Cetirizine 500mg', 141.37, 4, 565.48),
(16, 8, 43, 'Pantoprazole 500mg', 38.38, 3, 115.14),
(17, 8, 6, 'Atorvastatin 10mg', 55.00, 4, 220.00),
(18, 8, 100, 'Vitamin D3 Syrup', 781.24, 3, 2343.72),
(19, 9, 89, 'Omeprazole Syrup', 737.22, 5, 3686.10),
(20, 9, 7, 'Azithromycin 500mg', 180.00, 5, 900.00),
(21, 9, 112, 'Metformin 250mg', 601.77, 3, 1805.31),
(22, 10, 29, 'Atorvastatin 10mg', 354.21, 2, 708.42),
(23, 10, 9, 'Cough Syrup 100ml', 85.00, 5, 425.00),
(24, 10, 31, 'Cetirizine 250mg', 140.43, 1, 140.43),
(25, 11, 117, 'Metformin 10mg', 613.48, 3, 1840.44),
(26, 11, 55, 'Pantoprazole 250mg', 661.89, 4, 2647.56),
(27, 11, 106, 'Metformin Syrup', 765.71, 5, 3828.55),
(28, 12, 74, 'Azithromycin 10mg', 697.53, 1, 697.53),
(29, 12, 85, 'Calcium 500mg', 557.42, 5, 2787.10),
(30, 12, 80, 'Calcium Syrup', 643.06, 3, 1929.18),
(31, 13, 91, 'Cetirizine 250mg', 24.86, 3, 74.58),
(32, 13, 65, 'Cetirizine 10mg', 259.20, 2, 518.40),
(33, 14, 92, 'Cetirizine 500mg', 141.37, 5, 706.85),
(34, 14, 99, 'Vitamin D3 500mg', 360.82, 5, 1804.10),
(35, 14, 88, 'Paracetamol 500mg', 295.54, 1, 295.54),
(36, 15, 26, 'Omeprazole 10mg', 556.12, 5, 2780.60),
(37, 15, 61, 'Paracetamol 250mg', 51.88, 5, 259.40),
(38, 16, 28, 'Paracetamol Syrup', 325.91, 4, 1303.64),
(39, 16, 106, 'Metformin Syrup', 765.71, 4, 3062.84),
(40, 17, 13, 'Dolo 650mg', 18.00, 2, 36.00),
(41, 17, 57, 'Omeprazole Syrup', 636.77, 1, 636.77),
(42, 17, 52, 'Metformin 10mg', 423.07, 1, 423.07),
(43, 18, 10, 'Vitamin D3 60K', 95.00, 4, 380.00),
(44, 19, 62, 'Omeprazole Syrup', 674.03, 1, 674.03),
(45, 19, 48, 'Paracetamol 250mg', 290.52, 5, 1452.60),
(46, 19, 115, 'Pantoprazole 250mg', 665.17, 5, 3325.85),
(47, 20, 90, 'Calcium 500mg', 508.31, 4, 2033.24),
(48, 20, 8, 'Pantoprazole 40mg', 50.00, 3, 150.00),
(49, 21, 67, 'Vitamin D3 Syrup', 598.37, 4, 2393.48),
(50, 22, 65, 'Cetirizine 10mg', 259.20, 5, 1296.00),
(51, 22, 7, 'Azithromycin 500mg', 180.00, 2, 360.00),
(52, 23, 31, 'Cetirizine 250mg', 140.43, 5, 702.15),
(53, 23, 7, 'Azithromycin 500mg', 180.00, 1, 180.00),
(54, 23, 64, 'Cetirizine 10mg', 490.41, 4, 1961.64),
(55, 24, 40, 'Atorvastatin 10mg', 764.99, 3, 2294.97),
(56, 24, 100, 'Vitamin D3 Syrup', 781.24, 4, 3124.96),
(57, 24, 106, 'Metformin Syrup', 765.71, 1, 765.71),
(58, 25, 117, 'Metformin 10mg', 613.48, 1, 613.48),
(59, 25, 109, 'Amoxicillin 250mg', 468.04, 3, 1404.12),
(60, 26, 17, 'Omeprazole 250mg', 566.25, 1, 566.25),
(61, 26, 83, 'Amoxicillin Syrup', 790.79, 1, 790.79),
(62, 26, 52, 'Metformin 10mg', 423.07, 4, 1692.28),
(63, 27, 38, 'Azithromycin Syrup', 527.58, 1, 527.58),
(64, 28, 12, 'Multivitamin Capsules', 120.00, 3, 360.00),
(65, 29, 112, 'Metformin 250mg', 601.77, 4, 2407.08),
(66, 29, 93, 'Cetirizine 500mg', 263.76, 1, 263.76),
(67, 29, 91, 'Cetirizine 250mg', 24.86, 1, 24.86),
(68, 30, 105, 'Pantoprazole 250mg', 452.25, 3, 1356.75),
(69, 30, 58, 'Cetirizine 250mg', 243.87, 2, 487.74),
(70, 31, 58, 'Cetirizine 250mg', 243.87, 5, 1219.35),
(71, 31, 9, 'Cough Syrup 100ml', 85.00, 2, 170.00),
(72, 31, 114, 'Metformin Syrup', 705.08, 1, 705.08),
(73, 32, 97, 'Vitamin D3 500mg', 360.20, 4, 1440.80),
(74, 33, 33, 'Omeprazole Syrup', 267.41, 5, 1337.05),
(75, 34, 68, 'Omeprazole 500mg', 159.65, 2, 319.30),
(76, 34, 87, 'Azithromycin 250mg', 317.27, 4, 1269.08),
(77, 35, 90, 'Calcium 500mg', 508.31, 4, 2033.24),
(78, 36, 19, 'Amoxicillin 250mg', 69.22, 2, 138.44),
(79, 37, 95, 'Paracetamol 10mg', 759.96, 5, 3799.80),
(80, 37, 102, 'Paracetamol 10mg', 132.59, 5, 662.95),
(81, 38, 82, 'Metformin 500mg', 116.93, 1, 116.93),
(82, 39, 16, 'Azithromycin 10mg', 594.77, 2, 1189.54),
(83, 39, 86, 'Amoxicillin Syrup', 796.94, 4, 3187.76),
(84, 39, 4, 'Omeprazole 20mg', 45.00, 5, 225.00),
(85, 40, 112, 'Metformin 250mg', 601.77, 2, 1203.54),
(86, 40, 24, 'Atorvastatin 10mg', 746.50, 1, 746.50),
(87, 40, 71, 'Omeprazole 10mg', 424.71, 1, 424.71),
(88, 41, 71, 'Omeprazole 10mg', 424.71, 3, 1274.13),
(89, 41, 104, 'Azithromycin 250mg', 39.91, 3, 119.73),
(90, 41, 88, 'Paracetamol 500mg', 295.54, 5, 1477.70),
(91, 42, 73, 'Metformin 250mg', 383.01, 3, 1149.03),
(92, 43, 90, 'Calcium 500mg', 508.31, 5, 2541.55),
(93, 43, 53, 'Vitamin D3 500mg', 16.00, 3, 48.00),
(94, 44, 56, 'Pantoprazole 10mg', 559.30, 1, 559.30),
(95, 44, 34, 'Atorvastatin Syrup', 500.16, 4, 2000.64),
(96, 44, 85, 'Calcium 500mg', 557.42, 1, 557.42),
(97, 45, 40, 'Atorvastatin 10mg', 764.99, 3, 2294.97),
(98, 45, 94, 'Metformin Syrup', 763.84, 1, 763.84),
(99, 46, 45, 'Calcium 500mg', 80.82, 5, 404.10),
(100, 46, 92, 'Cetirizine 500mg', 141.37, 1, 141.37),
(101, 47, 8, 'Pantoprazole 40mg', 50.00, 5, 250.00),
(102, 48, 54, 'Vitamin D3 500mg', 514.73, 2, 1029.46),
(103, 48, 60, 'Amoxicillin 500mg', 231.52, 3, 694.56),
(104, 49, 29, 'Atorvastatin 10mg', 354.21, 3, 1062.63),
(105, 50, 57, 'Omeprazole Syrup', 636.77, 5, 3183.85),
(106, 51, 3, 'Amoxicillin 250mg', 120.00, 2, 240.00),
(107, 52, 81, 'Vitamin D3 500mg', 542.83, 4, 2171.32),
(108, 52, 19, 'Amoxicillin 250mg', 69.22, 2, 138.44),
(109, 52, 100, 'Vitamin D3 Syrup', 781.24, 4, 3124.96),
(110, 53, 3, 'Amoxicillin 250mg', 120.00, 5, 600.00),
(111, 53, 74, 'Azithromycin 10mg', 697.53, 4, 2790.12),
(112, 53, 83, 'Amoxicillin Syrup', 790.79, 3, 2372.37),
(113, 54, 24, 'Atorvastatin 10mg', 746.50, 4, 2986.00),
(114, 54, 61, 'Paracetamol 250mg', 51.88, 4, 207.52),
(115, 55, 25, 'Paracetamol 500mg', 610.93, 4, 2443.72),
(116, 56, 96, 'Paracetamol 500mg', 270.43, 4, 1081.72),
(117, 57, 33, 'Omeprazole Syrup', 267.41, 2, 534.82),
(118, 58, 50, 'Paracetamol 10mg', 720.30, 5, 3601.50),
(119, 58, 116, 'Metformin 10mg', 68.38, 4, 273.52),
(120, 59, 22, 'Azithromycin 10mg', 581.89, 3, 1745.67),
(121, 59, 118, 'Amoxicillin 10mg', 674.78, 5, 3373.90),
(122, 60, 47, 'Amoxicillin 10mg', 153.36, 4, 613.44),
(123, 61, 32, 'Atorvastatin 500mg', 56.70, 3, 170.10),
(124, 62, 90, 'Calcium 500mg', 508.31, 4, 2033.24),
(125, 62, 78, 'Calcium 10mg', 257.83, 5, 1289.15),
(126, 62, 116, 'Metformin 10mg', 68.38, 5, 341.90),
(127, 63, 72, 'Atorvastatin 500mg', 736.52, 2, 1473.04),
(128, 63, 48, 'Paracetamol 250mg', 290.52, 3, 871.56),
(129, 64, 43, 'Pantoprazole 500mg', 38.38, 2, 76.76),
(130, 65, 117, 'Metformin 10mg', 613.48, 4, 2453.92),
(131, 65, 66, 'Atorvastatin 250mg', 324.34, 3, 973.02),
(132, 66, 27, 'Atorvastatin Syrup', 701.05, 2, 1402.10),
(133, 66, 44, 'Vitamin D3 250mg', 531.83, 4, 2127.32),
(134, 67, 34, 'Atorvastatin Syrup', 500.16, 5, 2500.80),
(135, 67, 71, 'Omeprazole 10mg', 424.71, 1, 424.71),
(136, 68, 39, 'Amoxicillin 250mg', 341.04, 3, 1023.12),
(137, 68, 35, 'Paracetamol 10mg', 139.55, 5, 697.75),
(138, 69, 34, 'Atorvastatin Syrup', 500.16, 2, 1000.32),
(139, 69, 94, 'Metformin Syrup', 763.84, 5, 3819.20),
(140, 69, 64, 'Cetirizine 10mg', 490.41, 1, 490.41),
(141, 70, 58, 'Cetirizine 250mg', 243.87, 1, 243.87),
(142, 71, 109, 'Amoxicillin 250mg', 468.04, 3, 1404.12),
(143, 71, 40, 'Atorvastatin 10mg', 764.99, 1, 764.99),
(144, 71, 15, 'Dettol Liquid 500ml', 145.00, 3, 435.00),
(145, 72, 70, 'Atorvastatin 500mg', 561.85, 5, 2809.25),
(146, 73, 15, 'Dettol Liquid 500ml', 145.00, 1, 145.00),
(147, 74, 22, 'Azithromycin 10mg', 581.89, 4, 2327.56),
(148, 74, 105, 'Pantoprazole 250mg', 452.25, 2, 904.50),
(149, 74, 20, 'Pantoprazole Syrup', 61.32, 4, 245.28),
(150, 75, 25, 'Paracetamol 500mg', 610.93, 1, 610.93),
(151, 75, 65, 'Cetirizine 10mg', 259.20, 3, 777.60),
(152, 75, 106, 'Metformin Syrup', 765.71, 3, 2297.13),
(153, 76, 111, 'Pantoprazole 250mg', 192.41, 4, 769.64),
(154, 77, 59, 'Paracetamol 250mg', 494.52, 3, 1483.56),
(155, 78, 75, 'Cetirizine 10mg', 49.36, 1, 49.36),
(156, 78, 85, 'Calcium 500mg', 557.42, 5, 2787.10),
(157, 78, 10, 'Vitamin D3 60K', 95.00, 2, 190.00),
(158, 79, 52, 'Metformin 10mg', 423.07, 3, 1269.21),
(159, 80, 47, 'Amoxicillin 10mg', 153.36, 2, 306.72),
(160, 80, 21, 'Cetirizine 500mg', 538.61, 2, 1077.22),
(161, 80, 21, 'Cetirizine 500mg', 538.61, 1, 538.61),
(162, 81, 29, 'Atorvastatin 10mg', 354.21, 1, 354.21),
(163, 82, 110, 'Pantoprazole Syrup', 150.70, 2, 301.40),
(164, 82, 53, 'Vitamin D3 500mg', 16.00, 1, 16.00),
(165, 82, 93, 'Cetirizine 500mg', 263.76, 3, 791.28),
(166, 83, 2, 'Cetirizine 10mg', 25.00, 1, 25.00),
(167, 84, 87, 'Azithromycin 250mg', 317.27, 5, 1586.35),
(168, 84, 98, 'Calcium Syrup', 260.10, 3, 780.30),
(169, 85, 56, 'Pantoprazole 10mg', 559.30, 5, 2796.50),
(170, 85, 95, 'Paracetamol 10mg', 759.96, 2, 1519.92),
(171, 86, 40, 'Atorvastatin 10mg', 764.99, 1, 764.99),
(172, 86, 84, 'Pantoprazole 500mg', 109.51, 5, 547.55),
(173, 86, 38, 'Azithromycin Syrup', 527.58, 5, 2637.90),
(174, 87, 40, 'Atorvastatin 10mg', 764.99, 5, 3824.95),
(175, 87, 38, 'Azithromycin Syrup', 527.58, 3, 1582.74),
(176, 87, 5, 'Metformin 500mg', 35.00, 5, 175.00),
(177, 88, 92, 'Cetirizine 500mg', 141.37, 4, 565.48),
(178, 88, 30, 'Azithromycin Syrup', 677.21, 5, 3386.05),
(179, 89, 24, 'Atorvastatin 10mg', 746.50, 5, 3732.50),
(180, 89, 69, 'Calcium 500mg', 689.66, 3, 2068.98),
(181, 90, 105, 'Pantoprazole 250mg', 452.25, 5, 2261.25),
(182, 90, 52, 'Metformin 10mg', 423.07, 2, 846.14),
(183, 91, 12, 'Multivitamin Capsules', 120.00, 1, 120.00),
(184, 91, 5, 'Metformin 500mg', 35.00, 1, 35.00),
(185, 91, 118, 'Amoxicillin 10mg', 674.78, 5, 3373.90),
(186, 92, 97, 'Vitamin D3 500mg', 360.20, 5, 1801.00),
(187, 92, 46, 'Amoxicillin Syrup', 591.45, 5, 2957.25),
(188, 92, 36, 'Omeprazole 500mg', 221.29, 3, 663.87),
(189, 93, 113, 'Amoxicillin 500mg', 415.16, 2, 830.32),
(190, 93, 49, 'Azithromycin 500mg', 185.06, 3, 555.18),
(191, 93, 17, 'Omeprazole 250mg', 566.25, 4, 2265.00),
(192, 94, 82, 'Metformin 500mg', 116.93, 1, 116.93),
(193, 94, 62, 'Omeprazole Syrup', 674.03, 3, 2022.09),
(194, 95, 26, 'Omeprazole 10mg', 556.12, 2, 1112.24),
(195, 95, 63, 'Azithromycin 250mg', 602.82, 4, 2411.28),
(196, 96, 10, 'Vitamin D3 60K', 95.00, 2, 190.00),
(197, 96, 79, 'Metformin 250mg', 603.92, 1, 603.92),
(198, 97, 17, 'Omeprazole 250mg', 566.25, 2, 1132.50),
(199, 97, 12, 'Multivitamin Capsules', 120.00, 1, 120.00),
(200, 97, 51, 'Pantoprazole 250mg', 95.27, 3, 285.81),
(201, 98, 29, 'Atorvastatin 10mg', 354.21, 2, 708.42),
(202, 99, 30, 'Azithromycin Syrup', 677.21, 3, 2031.63),
(203, 99, 44, 'Vitamin D3 250mg', 531.83, 2, 1063.66),
(204, 99, 107, 'Omeprazole 500mg', 42.72, 3, 128.16),
(205, 100, 11, 'Calcium Tablets', 65.00, 3, 195.00),
(206, 100, 86, 'Amoxicillin Syrup', 796.94, 5, 3984.70),
(207, 100, 36, 'Omeprazole 500mg', 221.29, 5, 1106.45),
(208, 101, 58, 'Cetirizine 250mg', 243.87, 1, 243.87),
(209, 102, 46, 'Amoxicillin Syrup', 591.45, 9, 5323.05);

-- --------------------------------------------------------

--
-- Table structure for table `customers`
--

CREATE TABLE `customers` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `customers`
--

INSERT INTO `customers` (`id`, `name`, `phone`, `email`, `address`, `created_at`, `updated_at`) VALUES
(1, 'Meera Shah', '9867155219', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(2, 'Prisha Patel', '9860065845', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(3, 'Meera Mehta', '9891994349', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(4, 'Ishaan Mehta', '9885481360', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(5, 'Dhara Trivedi', '9874480657', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(6, 'Dhara Shah', '9877794449', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(7, 'Dhara Desai', '9856717113', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(8, 'Kabir Desai', '9844412104', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(9, 'Dhara Trivedi', '9831981506', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(10, 'Meera Trivedi', '9839230771', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(11, 'Jiya Shah', '9881281466', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(12, 'Jiya Choksi', '9856408520', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(13, 'Ishaan Patel', '9841249249', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(14, 'Meera Choksi', '9819896506', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(15, 'Kabir Patel', '9890711305', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(16, 'Kabir Trivedi', '9862348535', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(17, 'Meera Patel', '9817514096', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(18, 'Kabir Trivedi', '9887848232', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(19, 'Ishaan Mehta', '9854976958', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(20, 'Kabir Mehta', '9897563514', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(21, 'Naitik Shah', '9851391266', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(22, 'Jiya Gajjar', '9871550784', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(23, 'Jiya Mehta', '9840329359', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(24, 'Jiya Patel', '9821794358', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(25, 'Meera Trivedi', '9894844533', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(26, 'Aarav Mehta', '9872165217', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(27, 'Aarav Mehta', '9815711822', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(28, 'Jiya Trivedi', '9842889508', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(29, 'Naitik Trivedi', '9813298845', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(30, 'Ishaan Mehta', '9851317736', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(31, 'Jiya Shah', '9885454077', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(32, 'Kabir Shah', '9816699956', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(33, 'Dhara Trivedi', '9878317808', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(34, 'Prisha Mehta', '9861949446', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(35, 'Aarav Desai', '9824037198', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(36, 'Dhara Trivedi', '9868879116', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(37, 'Kabir Patel', '9811612032', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(38, 'Prisha Shah', '9849786603', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(39, 'Prisha Choksi', '9822470141', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(40, 'Kabir Desai', '9878644126', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(41, 'Meera Desai', '9850755013', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(42, 'Prisha Patel', '9850381049', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(43, 'Prisha Mehta', '9817249269', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(44, 'Kabir Gajjar', '9863947550', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(45, 'Aarav Shah', '9830960343', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(46, 'Prisha Trivedi', '9869619864', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(47, 'Ishaan Desai', '9837902560', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(48, 'Aarav Shah', '9848019290', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(49, 'Meera Desai', '9886186224', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(50, 'Ishaan Patel', '9897904868', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(51, 'Jiya Mehta', '9857784537', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(52, 'Meera Shah', '9831346968', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(53, 'Jiya Shah', '9878436587', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(54, 'Dhara Desai', '9893732120', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(55, 'Naitik Gajjar', '9810409760', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(56, 'Meera Choksi', '9853915278', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(57, 'Kabir Choksi', '9869916500', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(58, 'Prisha Gajjar', '9883272001', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(59, 'Dhara Desai', '9814883550', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(60, 'Ishaan Desai', '9885006126', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(61, 'Dhara Gajjar', '9885225280', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(62, 'Ishaan Desai', '9849730460', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(63, 'Jiya Trivedi', '9882154166', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(64, 'Ishaan Choksi', '9895983633', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(65, 'Aarav Choksi', '9885088067', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(66, 'Ishaan Gajjar', '9833315291', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(67, 'Meera Gajjar', '9825927844', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(68, 'Naitik Shah', '9812753144', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(69, 'Kabir Desai', '9810871426', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(70, 'Dhara Patel', '9865746473', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(71, 'Kabir Mehta', '9846750764', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(72, 'Ishaan Patel', '9899356059', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(73, 'Naitik Gajjar', '9834990132', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(74, 'Meera Desai', '9840010510', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(75, 'Ishaan Desai', '9839620368', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(76, 'Ishaan Trivedi', '9893393032', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(77, 'Aarav Shah', '9861426323', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(78, 'Meera Patel', '9850436877', NULL, 'Ahmedabad, Gujarat', '2026-03-14 10:52:38', '2026-03-14 10:52:38'),
(79, 'HASYA  PATEL', '7862023272', 'studyfor1505@gmail.com', '', '2026-03-14 11:55:47', '2026-03-14 11:55:47');

-- --------------------------------------------------------

--
-- Stand-in structure for view `customer_purchase_summary`
-- (See below for the actual view)
--
CREATE TABLE `customer_purchase_summary` (
`customer_id` int(11)
,`customer_name` varchar(100)
,`phone` varchar(15)
,`total_purchases` bigint(21)
,`total_spent` decimal(32,2)
,`last_purchase_date` timestamp
,`unique_medicines_purchased` bigint(21)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `low_stock_items`
-- (See below for the actual view)
--
CREATE TABLE `low_stock_items` (
`id` int(11)
,`name` varchar(200)
,`manufacturer` varchar(100)
,`stock_quantity` int(11)
,`min_stock_level` int(11)
,`price` decimal(10,2)
,`category` varchar(100)
,`shelf_location` varchar(50)
,`shortage_quantity` bigint(12)
);

-- --------------------------------------------------------

--
-- Table structure for table `pending_orders`
--

CREATE TABLE `pending_orders` (
  `id` int(11) NOT NULL,
  `order_number` varchar(50) NOT NULL,
  `customer_id` int(11) DEFAULT NULL,
  `customer_name` varchar(100) NOT NULL,
  `phone` varchar(15) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `subtotal` decimal(10,2) NOT NULL DEFAULT 0.00,
  `gst` decimal(10,2) NOT NULL DEFAULT 0.00,
  `total_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `payment_method` enum('upi') NOT NULL DEFAULT 'upi',
  `payment_status` enum('pending','approved','rejected','expired') NOT NULL DEFAULT 'pending',
  `cart_data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'Stores cart items as JSON' CHECK (json_valid(`cart_data`)),
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `approved_at` timestamp NULL DEFAULT NULL,
  `approved_by` int(11) DEFAULT NULL,
  `bill_id` int(11) DEFAULT NULL COMMENT 'Reference to created bill after approval'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `pending_orders`
--

INSERT INTO `pending_orders` (`id`, `order_number`, `customer_id`, `customer_name`, `phone`, `email`, `address`, `subtotal`, `gst`, `total_amount`, `payment_method`, `payment_status`, `cart_data`, `created_by`, `created_at`, `approved_at`, `approved_by`, `bill_id`) VALUES
(1, 'INV-20260314172547', 79, 'HASYA  PATEL', '7862023272', 'studyfor1505@gmail.com', '', 243.87, 29.26, 273.13, 'upi', 'approved', '[{\"batch_id\": 43, \"batch_number\": \"LOT-58-2025\", \"expiry_date\": \"2026-12-01\", \"id\": 58, \"name\": \"Cetirizine 250mg\", \"price\": 243.87, \"quantity\": 1, \"stock_quantity\": 93}]', 1, '2026-03-14 11:55:47', '2026-03-14 11:57:10', 1, 101),
(2, 'INV-20260315120754', 79, 'HASYA  PATEL', '7862023272', 'studyfor1505@gmail.com', 'shivpark B/26,dhrangdhra', 5323.05, 638.77, 5961.82, 'upi', 'approved', '[{\"batch_id\": 31, \"batch_number\": \"LOT-46-2025\", \"expiry_date\": \"2027-01-21\", \"id\": 46, \"name\": \"Amoxicillin Syrup\", \"price\": 591.45, \"quantity\": 9, \"stock_quantity\": 248}]', 1, '2026-03-15 06:37:54', '2026-03-15 06:37:59', 1, 102);

-- --------------------------------------------------------

--
-- Table structure for table `products`
--

CREATE TABLE `products` (
  `id` int(11) NOT NULL,
  `name` varchar(200) NOT NULL,
  `manufacturer` varchar(100) DEFAULT NULL,
  `price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `stock_quantity` int(11) NOT NULL DEFAULT 0 COMMENT 'Auto-calculated total from all batches',
  `min_stock_level` int(11) NOT NULL DEFAULT 15,
  `shelf_location` varchar(50) DEFAULT NULL,
  `category` varchar(100) DEFAULT NULL,
  `usage_type` varchar(200) DEFAULT NULL COMMENT 'Medical usage/indication',
  `batch_number` varchar(50) DEFAULT NULL COMMENT 'Legacy field - use product_batches table',
  `expiry_date` date DEFAULT NULL COMMENT 'Legacy field - use product_batches table',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `products`
--

INSERT INTO `products` (`id`, `name`, `manufacturer`, `price`, `stock_quantity`, `min_stock_level`, `shelf_location`, `category`, `usage_type`, `batch_number`, `expiry_date`, `created_at`, `updated_at`) VALUES
(1, 'Paracetamol 500mg', 'Sun Pharma', 15.00, 133, 20, 'A1', 'Pain Relief', 'Fever, Headache, Body Pain', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(2, 'Cetirizine 10mg', 'Cipla', 25.00, 33, 20, 'A2', 'Antihistamine', 'Allergy, Cold, Runny Nose', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(3, 'Amoxicillin 250mg', 'Dr. Reddy\'s', 120.00, 12, 15, 'B1', 'Antibiotic', 'Bacterial Infection', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(4, 'Omeprazole 20mg', 'Lupin', 45.00, 49, 15, 'B2', 'Antacid', 'Acidity, Gastritis, Ulcer', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(5, 'Metformin 500mg', 'Mankind Pharma', 35.00, 155, 20, 'C1', 'Antidiabetic', 'Type 2 Diabetes', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(6, 'Atorvastatin 10mg', 'Torrent Pharma', 55.00, 25, 15, 'C2', 'Cholesterol', 'High Cholesterol', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(7, 'Azithromycin 500mg', 'Alkem Labs', 180.00, 14, 10, 'D1', 'Antibiotic', 'Respiratory Infection', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(8, 'Pantoprazole 40mg', 'Intas Pharma', 50.00, 60, 15, 'D2', 'Antacid', 'Acid Reflux, GERD', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(9, 'Cough Syrup 100ml', 'Himalaya', 85.00, 22, 15, 'E1', 'Cough Medicine', 'Cough, Cold', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(10, 'Vitamin D3 60K', 'Cipla', 95.00, 5, 20, 'E2', 'Vitamin Supplement', 'Vitamin D Deficiency', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(11, 'Calcium Tablets', 'Sun Pharma', 65.00, 40, 20, 'F1', 'Mineral Supplement', 'Bone Health', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(12, 'Multivitamin Capsules', 'HealthKart', 120.00, 33, 15, 'F2', 'Vitamin Supplement', 'General Health', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(13, 'Dolo 650mg', 'Micro Labs', 18.00, 200, 30, 'A3', 'Pain Relief', 'Fever, Pain', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(14, 'Crocin Advance', 'GSK', 22.00, 150, 25, 'A4', 'Pain Relief', 'Fast Fever Relief', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(15, 'Dettol Liquid 500ml', 'Reckitt Benckiser', 145.00, 10, 10, 'G1', 'Antiseptic', 'Wound Cleaning, Disinfection', NULL, NULL, '2026-03-14 10:36:18', '2026-03-14 11:27:20'),
(16, 'Azithromycin 10mg', 'Sun Pharma', 594.77, 12, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(17, 'Omeprazole 250mg', 'Cipla', 566.25, 1, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(18, 'Vitamin D3 500mg', 'Zydus', 246.23, 12, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(19, 'Amoxicillin 250mg', 'Intas', 69.22, 4, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(20, 'Pantoprazole Syrup', 'Torrent', 61.32, 12, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(21, 'Cetirizine 500mg', 'Alembic', 538.61, 8, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(22, 'Azithromycin 10mg', 'Lupin', 581.89, 1, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(23, 'Omeprazole Syrup', 'Abbott', 618.20, 2, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(24, 'Atorvastatin 10mg', 'GSK', 746.50, 7, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(25, 'Paracetamol 500mg', 'Pfizer', 610.93, 6, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(26, 'Omeprazole 10mg', 'Merck', 556.12, 10, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(27, 'Atorvastatin Syrup', 'Alkem', 701.05, 6, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(28, 'Paracetamol Syrup', 'Glenmark', 325.91, 12, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(29, 'Atorvastatin 10mg', 'Dr. Reddy\'s', 354.21, 2, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(30, 'Azithromycin Syrup', 'Mankind', 677.21, 11, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(31, 'Cetirizine 250mg', 'Micro Labs', 140.43, 4, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(32, 'Atorvastatin 500mg', 'Sanofi', 56.70, 12, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(33, 'Omeprazole Syrup', 'Himalaya', 267.41, 10, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(34, 'Atorvastatin Syrup', 'Ajanta', 500.16, 11, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(35, 'Paracetamol 10mg', 'Sun Pharma', 139.55, 1, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(36, 'Omeprazole 500mg', 'Cipla', 221.29, 14, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(37, 'Atorvastatin 500mg', 'Zydus', 290.33, 7, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(38, 'Azithromycin Syrup', 'Intas', 527.58, 1, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(39, 'Amoxicillin 250mg', 'Torrent', 341.04, 8, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(40, 'Atorvastatin 10mg', 'Alembic', 764.99, 10, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(41, 'Pantoprazole 10mg', 'Lupin', 306.75, 174, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(42, 'Amoxicillin 250mg', 'Abbott', 85.63, 76, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(43, 'Pantoprazole 500mg', 'GSK', 38.38, 191, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(44, 'Vitamin D3 250mg', 'Pfizer', 531.83, 186, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(45, 'Calcium 500mg', 'Merck', 80.82, 114, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(46, 'Amoxicillin Syrup', 'Alkem', 591.45, 239, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-15 06:37:59'),
(47, 'Amoxicillin 10mg', 'Glenmark', 153.36, 144, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(48, 'Paracetamol 250mg', 'Dr. Reddy\'s', 290.52, 166, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(49, 'Azithromycin 500mg', 'Mankind', 185.06, 144, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(50, 'Paracetamol 10mg', 'Micro Labs', 720.30, 130, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(51, 'Pantoprazole 250mg', 'Sanofi', 95.27, 185, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(52, 'Metformin 10mg', 'Himalaya', 423.07, 103, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(53, 'Vitamin D3 500mg', 'Ajanta', 16.00, 139, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(54, 'Vitamin D3 500mg', 'Sun Pharma', 514.73, 166, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(55, 'Pantoprazole 250mg', 'Cipla', 661.89, 115, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(56, 'Pantoprazole 10mg', 'Zydus', 559.30, 170, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(57, 'Omeprazole Syrup', 'Intas', 636.77, 182, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(58, 'Cetirizine 250mg', 'Torrent', 243.87, 93, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-15 06:27:57'),
(59, 'Paracetamol 250mg', 'Alembic', 494.52, 136, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-15 07:28:09'),
(60, 'Amoxicillin 500mg', 'Lupin', 231.52, 151, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(61, 'Paracetamol 250mg', 'Abbott', 51.88, 113, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(62, 'Omeprazole Syrup', 'GSK', 674.03, 134, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(63, 'Azithromycin 250mg', 'Pfizer', 602.82, 108, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(64, 'Cetirizine 10mg', 'Merck', 490.41, 217, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(65, 'Cetirizine 10mg', 'Alkem', 259.20, 171, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-15 06:24:31'),
(66, 'Atorvastatin 250mg', 'Glenmark', 324.34, 219, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(67, 'Vitamin D3 Syrup', 'Dr. Reddy\'s', 598.37, 215, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(68, 'Omeprazole 500mg', 'Mankind', 159.65, 78, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(69, 'Calcium 500mg', 'Micro Labs', 689.66, 60, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(70, 'Atorvastatin 500mg', 'Sanofi', 561.85, 116, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(71, 'Omeprazole 10mg', 'Himalaya', 424.71, 196, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(72, 'Atorvastatin 500mg', 'Ajanta', 736.52, 95, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(73, 'Metformin 250mg', 'Sun Pharma', 383.01, 225, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-15 07:41:38'),
(74, 'Azithromycin 10mg', 'Cipla', 697.53, 235, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(75, 'Cetirizine 10mg', 'Zydus', 49.36, 153, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(76, 'Metformin Syrup', 'Intas', 564.33, 164, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(77, 'Amoxicillin 10mg', 'Torrent', 771.49, 110, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(78, 'Calcium 10mg', 'Alembic', 257.83, 249, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(79, 'Metformin 250mg', 'Lupin', 603.92, 234, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(80, 'Calcium Syrup', 'Abbott', 643.06, 158, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(81, 'Vitamin D3 500mg', 'GSK', 542.83, 214, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(82, 'Metformin 500mg', 'Pfizer', 116.93, 85, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(83, 'Amoxicillin Syrup', 'Merck', 790.79, 239, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(84, 'Pantoprazole 500mg', 'Alkem', 109.51, 221, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(85, 'Calcium 500mg', 'Glenmark', 557.42, 127, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(86, 'Amoxicillin Syrup', 'Dr. Reddy\'s', 796.94, 190, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(87, 'Azithromycin 250mg', 'Mankind', 317.27, 228, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(88, 'Paracetamol 500mg', 'Micro Labs', 295.54, 112, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(89, 'Omeprazole Syrup', 'Sanofi', 737.22, 53, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(90, 'Calcium 500mg', 'Himalaya', 508.31, 167, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(91, 'Cetirizine 250mg', 'Ajanta', 24.86, 238, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(92, 'Cetirizine 500mg', 'Sun Pharma', 141.37, 197, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(93, 'Cetirizine 500mg', 'Cipla', 263.76, 120, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-15 07:06:05'),
(94, 'Metformin Syrup', 'Zydus', 763.84, 147, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(95, 'Paracetamol 10mg', 'Intas', 759.96, 70, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(96, 'Paracetamol 500mg', 'Torrent', 270.43, 201, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(97, 'Vitamin D3 500mg', 'Alembic', 360.20, 164, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(98, 'Calcium Syrup', 'Lupin', 260.10, 160, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(99, 'Vitamin D3 500mg', 'Abbott', 360.82, 90, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(100, 'Vitamin D3 Syrup', 'GSK', 781.24, 229, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(101, 'Omeprazole 500mg', 'Pfizer', 284.32, 151, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(102, 'Paracetamol 10mg', 'Merck', 132.59, 97, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(103, 'Calcium 500mg', 'Alkem', 432.83, 188, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(104, 'Azithromycin 250mg', 'Glenmark', 39.91, 147, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(105, 'Pantoprazole 250mg', 'Dr. Reddy\'s', 452.25, 239, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(106, 'Metformin Syrup', 'Mankind', 765.71, 143, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(107, 'Omeprazole 500mg', 'Micro Labs', 42.72, 232, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(108, 'Omeprazole 500mg', 'Sanofi', 613.86, 220, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(109, 'Amoxicillin 250mg', 'Himalaya', 468.04, 120, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(110, 'Pantoprazole Syrup', 'Ajanta', 150.70, 64, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-15 07:12:34'),
(111, 'Pantoprazole 250mg', 'Sun Pharma', 192.41, 90, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(112, 'Metformin 250mg', 'Cipla', 601.77, 79, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(113, 'Amoxicillin 500mg', 'Zydus', 415.16, 121, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(114, 'Metformin Syrup', 'Intas', 705.08, 77, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(115, 'Pantoprazole 250mg', 'Torrent', 665.17, 166, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(116, 'Metformin 10mg', 'Alembic', 68.38, 188, 20, NULL, 'Capsule', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(117, 'Metformin 10mg', 'Lupin', 613.48, 186, 20, NULL, 'Tablet', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(118, 'Amoxicillin 10mg', 'Abbott', 674.78, 84, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(119, 'Vitamin D3 250mg', 'GSK', 180.65, 229, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(120, 'Metformin 500mg', 'Pfizer', 447.77, 92, 20, NULL, 'Liquid', NULL, NULL, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:03');

-- --------------------------------------------------------

--
-- Table structure for table `product_batches`
--

CREATE TABLE `product_batches` (
  `id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `batch_number` varchar(50) NOT NULL,
  `quantity` int(11) NOT NULL DEFAULT 0 COMMENT 'Available quantity in this batch',
  `expiry_date` date NOT NULL,
  `purchase_date` date DEFAULT curdate(),
  `cost_price` decimal(10,2) DEFAULT NULL COMMENT 'Purchase cost per unit',
  `supplier_id` int(11) DEFAULT NULL COMMENT 'Supplier who provided this batch',
  `shelf_location` varchar(50) DEFAULT NULL COMMENT 'Physical location',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `product_batches`
--

INSERT INTO `product_batches` (`id`, `product_id`, `batch_number`, `quantity`, `expiry_date`, `purchase_date`, `cost_price`, `supplier_id`, `shelf_location`, `created_at`, `updated_at`) VALUES
(1, 16, 'LOT-16-2025', 12, '2027-04-06', '2026-03-14', NULL, 16, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(2, 17, 'LOT-17-2025', 1, '2028-04-04', '2026-03-14', NULL, 14, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(3, 18, 'LOT-18-2025', 12, '2028-01-11', '2026-03-14', NULL, 22, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(4, 19, 'LOT-19-2025', 4, '2026-08-13', '2026-03-14', NULL, 14, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(5, 20, 'LOT-20-2025', 12, '2028-02-04', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(6, 21, 'LOT-21-2025', 8, '2028-04-28', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(7, 22, 'LOT-22-2025', 1, '2027-03-13', '2026-03-14', NULL, 16, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(8, 23, 'LOT-23-2025', 2, '2026-08-19', '2026-03-14', NULL, 14, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(9, 24, 'LOT-24-2025', 7, '2026-12-14', '2026-03-14', NULL, 4, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(10, 25, 'LOT-25-2025', 6, '2026-07-28', '2026-03-14', NULL, 6, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(11, 26, 'LOT-26-2025', 10, '2027-10-22', '2026-03-14', NULL, 17, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(12, 27, 'LOT-27-2025', 6, '2027-09-16', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(13, 28, 'LOT-28-2025', 12, '2026-12-21', '2026-03-14', NULL, 4, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(14, 29, 'LOT-29-2025', 2, '2027-01-14', '2026-03-14', NULL, 22, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(15, 30, 'LOT-30-2025', 11, '2026-10-26', '2026-03-14', NULL, 19, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(16, 31, 'LOT-31-2025', 4, '2027-04-03', '2026-03-14', NULL, 24, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(17, 32, 'LOT-32-2025', 12, '2027-10-02', '2026-03-14', NULL, 11, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(18, 33, 'LOT-33-2025', 10, '2026-09-08', '2026-03-14', NULL, 11, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(19, 34, 'LOT-34-2025', 11, '2027-12-11', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(20, 35, 'LOT-35-2025', 1, '2028-01-19', '2026-03-14', NULL, 6, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(21, 36, 'LOT-36-2025', 14, '2027-10-29', '2026-03-14', NULL, 11, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(22, 37, 'LOT-37-2025', 7, '2027-01-26', '2026-03-14', NULL, 6, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(23, 38, 'LOT-38-2025', 1, '2026-10-24', '2026-03-14', NULL, 5, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(24, 39, 'LOT-39-2025', 8, '2026-12-27', '2026-03-14', NULL, 24, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(25, 40, 'LOT-40-2025', 10, '2027-08-05', '2026-03-14', NULL, 23, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(26, 41, 'LOT-41-2025', 174, '2027-12-22', '2026-03-14', NULL, 9, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(27, 42, 'LOT-42-2025', 76, '2028-03-22', '2026-03-14', NULL, 14, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(28, 43, 'LOT-43-2025', 191, '2027-08-15', '2026-03-14', NULL, 14, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(29, 44, 'LOT-44-2025', 186, '2026-11-20', '2026-03-14', NULL, 7, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(30, 45, 'LOT-45-2025', 114, '2028-03-15', '2026-03-14', NULL, 19, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(31, 46, 'LOT-46-2025', 239, '2027-01-21', '2026-03-14', NULL, 23, NULL, '2026-03-14 10:38:02', '2026-03-15 06:37:59'),
(32, 47, 'LOT-47-2025', 144, '2028-02-04', '2026-03-14', NULL, 23, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(33, 48, 'LOT-48-2025', 166, '2027-10-30', '2026-03-14', NULL, 6, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(34, 49, 'LOT-49-2025', 144, '2027-01-28', '2026-03-14', NULL, 6, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(35, 50, 'LOT-50-2025', 130, '2027-09-11', '2026-03-14', NULL, 23, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(36, 51, 'LOT-51-2025', 185, '2028-02-01', '2026-03-14', NULL, 15, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(37, 52, 'LOT-52-2025', 103, '2026-09-10', '2026-03-14', NULL, 13, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(38, 53, 'LOT-53-2025', 139, '2026-09-27', '2026-03-14', NULL, 11, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(39, 54, 'LOT-54-2025', 166, '2026-07-03', '2026-03-14', NULL, 25, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(40, 55, 'LOT-55-2025', 115, '2027-01-19', '2026-03-14', NULL, 16, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(41, 56, 'LOT-56-2025', 170, '2026-10-10', '2026-03-14', NULL, 16, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(42, 57, 'LOT-57-2025', 182, '2027-06-09', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(43, 58, 'LOT-58-2025', 92, '2026-12-01', '2026-03-14', NULL, 21, NULL, '2026-03-14 10:38:02', '2026-03-14 11:57:10'),
(44, 59, 'LOT-59-2025', 136, '2026-10-29', '2026-03-14', NULL, 25, NULL, '2026-03-14 10:38:02', '2026-03-15 07:28:09'),
(45, 60, 'LOT-60-2025', 151, '2027-04-06', '2026-03-14', NULL, 4, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(46, 61, 'LOT-61-2025', 113, '2028-04-15', '2026-03-14', NULL, 21, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(47, 62, 'LOT-62-2025', 134, '2028-01-05', '2026-03-14', NULL, 5, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(48, 63, 'LOT-63-2025', 108, '2027-12-18', '2026-03-14', NULL, 10, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(49, 64, 'LOT-64-2025', 217, '2027-05-24', '2026-03-14', NULL, 23, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(50, 65, 'LOT-65-2025', 168, '2028-01-19', '2026-03-14', NULL, 14, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(51, 66, 'LOT-66-2025', 219, '2026-09-29', '2026-03-14', NULL, 19, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(52, 67, 'LOT-67-2025', 215, '2028-01-07', '2026-03-14', NULL, 6, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(53, 68, 'LOT-68-2025', 78, '2028-03-25', '2026-03-14', NULL, 13, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(54, 69, 'LOT-69-2025', 60, '2027-04-22', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(55, 70, 'LOT-70-2025', 116, '2028-04-10', '2026-03-14', NULL, 8, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(56, 71, 'LOT-71-2025', 196, '2027-09-09', '2026-03-14', NULL, 12, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(57, 72, 'LOT-72-2025', 95, '2027-08-12', '2026-03-14', NULL, 9, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(58, 73, 'LOT-73-2025', 225, '2027-07-02', '2026-03-14', NULL, 21, NULL, '2026-03-14 10:38:02', '2026-03-15 07:41:38'),
(59, 74, 'LOT-74-2025', 235, '2027-03-17', '2026-03-14', NULL, 17, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(60, 75, 'LOT-75-2025', 153, '2026-08-30', '2026-03-14', NULL, 14, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(61, 76, 'LOT-76-2025', 164, '2027-09-25', '2026-03-14', NULL, 19, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(62, 77, 'LOT-77-2025', 110, '2027-02-19', '2026-03-14', NULL, 25, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(63, 78, 'LOT-78-2025', 249, '2027-12-27', '2026-03-14', NULL, 5, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(64, 79, 'LOT-79-2025', 234, '2027-06-24', '2026-03-14', NULL, 8, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(65, 80, 'LOT-80-2025', 158, '2027-11-23', '2026-03-14', NULL, 12, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(66, 81, 'LOT-81-2025', 214, '2028-04-22', '2026-03-14', NULL, 17, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(67, 82, 'LOT-82-2025', 85, '2027-04-08', '2026-03-14', NULL, 11, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(68, 83, 'LOT-83-2025', 239, '2026-12-10', '2026-03-14', NULL, 12, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(69, 84, 'LOT-84-2025', 221, '2027-08-08', '2026-03-14', NULL, 13, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(70, 85, 'LOT-85-2025', 127, '2027-08-11', '2026-03-14', NULL, 19, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(71, 86, 'LOT-86-2025', 190, '2027-08-13', '2026-03-14', NULL, 10, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(72, 87, 'LOT-87-2025', 228, '2026-10-06', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(73, 88, 'LOT-88-2025', 112, '2028-03-18', '2026-03-14', NULL, 18, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(74, 89, 'LOT-89-2025', 53, '2028-02-06', '2026-03-14', NULL, 9, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(75, 90, 'LOT-90-2025', 167, '2027-06-03', '2026-03-14', NULL, 5, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(76, 91, 'LOT-91-2025', 238, '2027-06-22', '2026-03-14', NULL, 13, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(77, 92, 'LOT-92-2025', 197, '2026-08-18', '2026-03-14', NULL, 17, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(78, 93, 'LOT-93-2025', 120, '2027-05-05', '2026-03-14', NULL, 23, NULL, '2026-03-14 10:38:02', '2026-03-15 07:06:05'),
(79, 94, 'LOT-94-2025', 147, '2027-10-30', '2026-03-14', NULL, 7, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(80, 95, 'LOT-95-2025', 70, '2027-09-02', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(81, 96, 'LOT-96-2025', 201, '2028-02-29', '2026-03-14', NULL, 25, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(82, 97, 'LOT-97-2025', 164, '2026-10-16', '2026-03-14', NULL, 23, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(83, 98, 'LOT-98-2025', 160, '2027-09-17', '2026-03-14', NULL, 18, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(84, 99, 'LOT-99-2025', 90, '2027-09-17', '2026-03-14', NULL, 19, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(85, 100, 'LOT-100-2025', 229, '2027-05-18', '2026-03-14', NULL, 9, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(86, 101, 'LOT-101-2025', 151, '2028-04-04', '2026-03-14', NULL, 12, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(87, 102, 'LOT-102-2025', 97, '2027-06-12', '2026-03-14', NULL, 9, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(88, 103, 'LOT-103-2025', 188, '2026-11-03', '2026-03-14', NULL, 4, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(89, 104, 'LOT-104-2025', 147, '2027-05-01', '2026-03-14', NULL, 19, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(90, 105, 'LOT-105-2025', 239, '2026-07-27', '2026-03-14', NULL, 18, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(91, 106, 'LOT-106-2025', 143, '2028-04-27', '2026-03-14', NULL, 8, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(92, 107, 'LOT-107-2025', 232, '2027-10-26', '2026-03-14', NULL, 22, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(93, 108, 'LOT-108-2025', 220, '2027-08-01', '2026-03-14', NULL, 22, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(94, 109, 'LOT-109-2025', 120, '2027-06-01', '2026-03-14', NULL, 5, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(95, 110, 'LOT-110-2025', 64, '2027-08-06', '2026-03-14', NULL, 9, NULL, '2026-03-14 10:38:02', '2026-03-15 07:12:34'),
(96, 111, 'LOT-111-2025', 90, '2027-12-03', '2026-03-14', NULL, 7, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(97, 112, 'LOT-112-2025', 79, '2027-04-18', '2026-03-14', NULL, 15, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(98, 113, 'LOT-113-2025', 121, '2027-06-22', '2026-03-14', NULL, 21, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(99, 114, 'LOT-114-2025', 77, '2026-07-11', '2026-03-14', NULL, 7, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(100, 115, 'LOT-115-2025', 166, '2027-12-20', '2026-03-14', NULL, 11, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(101, 116, 'LOT-116-2025', 188, '2027-12-28', '2026-03-14', NULL, 20, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(102, 117, 'LOT-117-2025', 186, '2027-12-18', '2026-03-14', NULL, 25, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(103, 118, 'LOT-118-2025', 84, '2027-01-07', '2026-03-14', NULL, 6, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(104, 119, 'LOT-119-2025', 229, '2028-01-23', '2026-03-14', NULL, 21, NULL, '2026-03-14 10:38:02', '2026-03-14 10:38:02'),
(105, 120, 'LOT-120-2025', 92, '2027-01-08', '2026-03-14', NULL, 22, NULL, '2026-03-14 10:38:03', '2026-03-14 10:38:03'),
(106, 1, 'EXP-2026-001', 45, '2026-03-16', '2026-03-14', 10.50, 1, 'A1-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(107, 2, 'EXP-2026-002', 12, '2026-03-19', '2026-03-14', 18.00, 2, 'A2-Mid', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(108, 3, 'EXP-2026-003', 8, '2026-03-21', '2026-03-14', 95.00, 3, 'B1-Bot', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(109, 4, 'EXP-2026-004', 30, '2026-03-24', '2026-03-14', 32.00, 4, 'B2-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(110, 5, 'EXP-2026-005', 100, '2026-03-26', '2026-03-14', 25.00, 5, 'C1-Mid', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(111, 6, 'EXP-2026-006', 25, '2026-03-29', '2026-03-14', 40.00, 1, 'C2-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(112, 7, 'EXP-2026-007', 14, '2026-04-01', '2026-03-14', 140.00, 2, 'D1-Bot', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(113, 8, 'EXP-2026-008', 60, '2026-04-03', '2026-03-14', 38.00, 3, 'D2-Mid', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(114, 9, 'EXP-2026-009', 22, '2026-04-05', '2026-03-14', 65.00, 4, 'E1-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(115, 10, 'EXP-2026-010', 5, '2026-04-08', '2026-03-14', 75.00, 5, 'E2-Mid', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(116, 11, 'EXP-2026-011', 40, '2026-04-11', '2026-03-14', 48.00, 1, 'F1-Bot', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(117, 12, 'EXP-2026-012', 33, '2026-04-13', '2026-03-14', 88.00, 2, 'F2-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(118, 13, 'EXP-2026-013', 200, '2026-04-15', '2026-03-14', 12.00, 3, 'A3-Mid', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(119, 14, 'EXP-2026-014', 150, '2026-04-18', '2026-03-14', 16.00, 4, 'A4-Bot', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(120, 15, 'EXP-2026-015', 10, '2026-04-21', '2026-03-14', 110.00, 5, 'G1-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(121, 1, 'EXP-2026-016', 88, '2026-04-23', '2026-03-14', 10.50, 1, 'A1-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(122, 2, 'EXP-2026-017', 21, '2026-04-25', '2026-03-14', 18.00, 2, 'A2-Mid', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(123, 3, 'EXP-2026-018', 4, '2026-04-28', '2026-03-14', 95.00, 3, 'B1-Bot', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(124, 4, 'EXP-2026-019', 19, '2026-05-01', '2026-03-14', 32.00, 4, 'B2-Top', '2026-03-14 11:27:20', '2026-03-14 11:27:20'),
(125, 5, 'EXP-2026-020', 55, '2026-05-02', '2026-03-14', 25.00, 5, 'C1-Mid', '2026-03-14 11:27:20', '2026-03-14 11:27:20');

--
-- Triggers `product_batches`
--
DELIMITER $$
CREATE TRIGGER `trg_batch_update_stock` AFTER INSERT ON `product_batches` FOR EACH ROW BEGIN
    UPDATE products 
    SET stock_quantity = (
        SELECT COALESCE(SUM(quantity), 0) 
        FROM product_batches 
        WHERE product_id = NEW.product_id
    )
    WHERE id = NEW.product_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_batch_update_stock_after_delete` AFTER DELETE ON `product_batches` FOR EACH ROW BEGIN
    UPDATE products 
    SET stock_quantity = (
        SELECT COALESCE(SUM(quantity), 0) 
        FROM product_batches 
        WHERE product_id = OLD.product_id
    )
    WHERE id = OLD.product_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_batch_update_stock_after_update` AFTER UPDATE ON `product_batches` FOR EACH ROW BEGIN
    UPDATE products 
    SET stock_quantity = (
        SELECT COALESCE(SUM(quantity), 0) 
        FROM product_batches 
        WHERE product_id = NEW.product_id
    )
    WHERE id = NEW.product_id;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `regular_purchases`
--

CREATE TABLE `regular_purchases` (
  `id` int(11) NOT NULL,
  `customer_id` int(11) NOT NULL,
  `product_id` int(11) DEFAULT NULL,
  `medicine_name` varchar(200) NOT NULL,
  `default_quantity` int(11) NOT NULL DEFAULT 1,
  `added_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `regular_purchases`
--

INSERT INTO `regular_purchases` (`id`, `customer_id`, `product_id`, `medicine_name`, `default_quantity`, `added_at`, `updated_at`) VALUES
(1, 4, 60, 'Amoxicillin 500mg', 1, '2026-03-14 10:42:14', '2026-03-14 10:42:14'),
(2, 4, NULL, 'paracetamol 650mg', 1, '2026-03-14 10:42:24', '2026-03-14 10:42:24'),
(3, 4, NULL, 'Atarax Drops', 1, '2026-03-14 10:42:31', '2026-03-14 10:42:31');

-- --------------------------------------------------------

--
-- Table structure for table `returns`
--

CREATE TABLE `returns` (
  `id` int(11) NOT NULL,
  `bill_id` int(11) DEFAULT NULL,
  `product_id` int(11) DEFAULT NULL,
  `quantity` int(11) DEFAULT NULL,
  `refund_amount` decimal(10,2) DEFAULT NULL,
  `return_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `reason` text DEFAULT NULL,
  `added_to_inventory` tinyint(1) DEFAULT 0,
  `processed_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `returns`
--

INSERT INTO `returns` (`id`, `bill_id`, `product_id`, `quantity`, `refund_amount`, `return_date`, `reason`, `added_to_inventory`, `processed_by`) VALUES
(1, 22, 65, 3, 777.60, '2026-03-15 06:24:31', NULL, 1, 1),
(2, 70, 58, 1, 243.87, '2026-03-15 06:27:57', NULL, 1, 1),
(3, 82, 93, 2, 527.52, '2026-03-15 07:06:05', NULL, 1, 1),
(4, 82, 110, 2, 301.40, '2026-03-15 07:06:38', NULL, 1, 1),
(5, 82, 110, 2, 301.40, '2026-03-15 07:12:34', NULL, 1, 1),
(6, 77, 59, 2, 989.04, '2026-03-15 07:28:09', NULL, 1, 1),
(7, 42, 73, 3, 1149.03, '2026-03-15 07:41:38', NULL, 1, 1);

-- --------------------------------------------------------

--
-- Stand-in structure for view `sales_summary`
-- (See below for the actual view)
--
CREATE TABLE `sales_summary` (
`sale_date` date
,`total_bills` bigint(21)
,`total_items_sold` bigint(21)
,`total_quantity` decimal(32,0)
,`total_subtotal` decimal(32,2)
,`total_gst` decimal(32,2)
,`total_revenue` decimal(32,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `settings`
--

CREATE TABLE `settings` (
  `id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_label` varchar(100) DEFAULT NULL,
  `setting_type` varchar(50) DEFAULT 'text',
  `setting_value` text DEFAULT NULL,
  `setting_description` varchar(255) DEFAULT NULL,
  `is_editable` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `settings`
--

INSERT INTO `settings` (`id`, `setting_key`, `setting_label`, `setting_type`, `setting_value`, `setting_description`, `is_editable`, `created_at`, `updated_at`) VALUES
(1, 'store_name', 'Store Name', 'text', 'MediStore Pro', 'Store Name', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(2, 'store_address', 'Store Address', 'address', '123 Medical Street, Health City, State - 123456', 'Store Address', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(3, 'store_phone', 'Store Phone', 'text', '+91-1234567890', 'Store Phone Number', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(4, 'store_email', 'Store Email', 'email', 'info@medistore.com', 'Store Email Address', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(5, 'store_gstin', 'Store GSTIN', 'text', '22AAAAA0000A1Z5', 'Store GSTIN', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(6, 'store_license_no', 'Drug License Number', 'text', 'DL-12345-ABC', 'Drug License Number', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(7, 'gst_rate', 'GST Rate (%)', 'percentage', '12.0', 'GST Rate Percentage', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(8, 'currency_symbol', 'Currency Symbol', 'text', '₹', 'Currency Symbol', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(9, 'invoice_prefix', 'Invoice Prefix', 'text', 'INV', 'Invoice Number Prefix', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(10, 'low_stock_threshold', 'Low Stock Threshold', 'number', '15', 'Low Stock Alert Threshold', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(11, 'items_per_page', 'Items Per Page', 'number', '50', 'Items Per Page in Lists', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(12, 'enable_expiry_alerts', 'Enable Expiry Alerts', 'boolean', '1', 'Enable Expiry Date Alerts', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(13, 'store_logo_url', 'Store Logo URL', 'text', '', 'Store Logo URL', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(14, 'primary_color', 'Primary Theme Color', 'text', '#4f46e5', 'Primary Theme Color', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(15, 'accent_color', 'Accent Theme Color', 'text', '#10b981', 'Accent Theme Color', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18'),
(16, 'upi_id', 'UPI ID', 'text', 'yourstore@upi', 'UPI ID for receiving payments (e.g., yourstore@paytm, yourstore@ybl)', 1, '2026-03-14 10:36:18', '2026-03-14 10:36:18');

-- --------------------------------------------------------

--
-- Table structure for table `suppliers`
--

CREATE TABLE `suppliers` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `company_name` varchar(150) DEFAULT NULL,
  `phone` varchar(15) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `gstin` varchar(15) DEFAULT NULL COMMENT 'GST Identification Number',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `suppliers`
--

INSERT INTO `suppliers` (`id`, `name`, `company_name`, `phone`, `email`, `address`, `gstin`, `created_at`, `updated_at`) VALUES
(1, 'Bimalbhai Mehta', 'Gokul Pharma Supplies', '9146948425', NULL, 'Ahmedabad, Gujarat', '24AAAAA1261A1Z5', '2026-03-14 10:52:38', '2026-03-16 16:40:13'),
(2, 'Rajeshbhai Shah', 'Shah Medical Agency', '9116044784', NULL, 'Ahmedabad, Gujarat', '24AAAAA7375A1Z5', '2026-03-14 10:52:38', '2026-03-14 11:17:22'),
(3, 'Ashokbhai Trivedi', 'Sabarmati Medical Agency', '9182663041', NULL, 'Ahmedabad, Gujarat', '24AAAAA4939A1Z5', '2026-03-14 10:52:38', '2026-03-14 11:17:22'),
(4, 'Pareshbhai Vora', 'Aminel Pharma Supplies', '9163054518', NULL, 'Ahmedabad, Gujarat', '24AAAAA9975A1Z5', '2026-03-14 10:52:38', '2026-03-16 16:39:16'),
(5, 'Mansukhbhai Patel', 'Sardar Pharma Distributors', '9116010289', NULL, 'Ahmedabad, Gujarat', '24AAAAA1814A1Z5', '2026-03-14 10:52:38', '2026-03-14 11:17:22'),
(6, 'Vinodbhai Desai', 'Akshar Health Wholesale', '9134675059', NULL, 'Ahmedabad, Gujarat', '24AAAAA5922A1Z5', '2026-03-14 10:52:38', '2026-03-16 16:41:08'),
(7, 'Hardikbhai Choksi', 'Sayaji Med-Trade', '9149171698', NULL, 'Ahmedabad, Gujarat', '24AAAAA7952A1Z5', '2026-03-14 10:52:38', '2026-03-14 11:17:22'),
(8, 'Gautambhai Gajjar', 'Vishwakarma Pharma', '9183014559', NULL, 'Ahmedabad, Gujarat', '24AAAAA3341A1Z5', '2026-03-14 10:52:38', '2026-03-14 10:52:38');

-- --------------------------------------------------------

--
-- Table structure for table `supplier_purchases`
--

CREATE TABLE `supplier_purchases` (
  `id` int(11) NOT NULL,
  `purchase_number` varchar(50) NOT NULL,
  `supplier_id` int(11) NOT NULL,
  `product_id` int(11) DEFAULT NULL,
  `medicine_name` varchar(200) NOT NULL,
  `quantity` int(11) NOT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `total_amount` decimal(10,2) NOT NULL,
  `status` enum('to_be_ordered','ordered','received') NOT NULL DEFAULT 'to_be_ordered',
  `order_date` date DEFAULT NULL,
  `expected_delivery_date` date DEFAULT NULL,
  `received_date` date DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `batch_created` tinyint(1) DEFAULT 0,
  `total_purchase_value` decimal(10,2) DEFAULT 0.00,
  `received_count` int(11) DEFAULT 0,
  `last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `supplier_purchases`
--

INSERT INTO `supplier_purchases` (`id`, `purchase_number`, `supplier_id`, `product_id`, `medicine_name`, `quantity`, `unit_price`, `total_amount`, `status`, `order_date`, `expected_delivery_date`, `received_date`, `notes`, `created_at`, `updated_at`, `batch_created`, `total_purchase_value`, `received_count`, `last_updated`) VALUES
(1, 'PO-26-000', 8, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2025-10-29', NULL, '2025-11-01', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(2, 'PO-26-001', 5, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-11-13', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(3, 'PO-26-002', 1, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2025-12-23', NULL, '2025-12-26', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(4, 'PO-26-003', 7, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2025-12-26', NULL, '2025-12-29', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(5, 'PO-26-004', 5, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2026-02-20', NULL, '2026-02-23', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(6, 'PO-26-005', 8, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2026-02-12', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(7, 'PO-26-006', 3, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2026-01-27', NULL, '2026-01-30', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(8, 'PO-26-007', 7, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-10-31', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(9, 'PO-26-008', 6, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-10-05', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(10, 'PO-26-009', 8, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-10-17', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(11, 'PO-26-010', 3, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2025-10-05', NULL, '2025-10-08', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(12, 'PO-26-011', 3, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2026-02-06', NULL, '2026-03-15', NULL, '2026-03-14 10:52:38', '2026-03-15 06:43:46', 1, 0.00, 0, '2026-03-15 07:37:42'),
(13, 'PO-26-012', 2, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2025-12-12', NULL, '2025-12-15', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(14, 'PO-26-013', 3, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2025-12-15', NULL, '2026-03-15', NULL, '2026-03-14 10:52:38', '2026-03-15 06:43:49', 1, 0.00, 0, '2026-03-15 07:37:42'),
(15, 'PO-26-014', 4, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-12-12', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(16, 'PO-26-015', 2, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-12-26', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(17, 'PO-26-016', 2, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-11-27', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(18, 'PO-26-017', 4, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-11-17', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(19, 'PO-26-018', 3, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'received', '2026-01-23', NULL, '2026-01-26', NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42'),
(20, 'PO-26-019', 7, NULL, 'Inventory Stock', 100, 50.00, 5000.00, 'ordered', '2025-10-30', NULL, NULL, NULL, '2026-03-14 10:52:38', '2026-03-14 10:52:38', 0, 0.00, 0, '2026-03-15 07:37:42');

-- --------------------------------------------------------

--
-- Stand-in structure for view `supplier_purchase_summary`
-- (See below for the actual view)
--
CREATE TABLE `supplier_purchase_summary` (
`supplier_id` int(11)
,`supplier_name` varchar(100)
,`company_name` varchar(150)
,`total_orders` bigint(21)
,`pending_orders` decimal(22,0)
,`ordered_count` decimal(22,0)
,`received_count` decimal(22,0)
,`total_purchase_value` decimal(32,2)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `top_selling_products`
-- (See below for the actual view)
--
CREATE TABLE `top_selling_products` (
`medicine_name` varchar(200)
,`product_id` int(11)
,`times_sold` bigint(21)
,`total_quantity_sold` decimal(32,0)
,`total_revenue` decimal(32,2)
,`average_price` decimal(14,6)
);

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL COMMENT 'SHA-256 hashed password',
  `full_name` varchar(100) NOT NULL,
  `role` enum('owner','cashier') NOT NULL DEFAULT 'cashier',
  `email` varchar(100) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_active` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `username`, `password`, `full_name`, `role`, `email`, `phone`, `created_at`, `updated_at`, `is_active`) VALUES
(1, 'admin', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'System Administrator', 'owner', 'admin@medistore.com', '+91-9876543210', '2026-03-14 10:36:18', '2026-03-14 10:36:18', 1),
(2, 'cashier', '10176e7b7b24d317acfcf8d2064cfd2f24e154f7b5a96603077d5ef813d6a6b6', 'Store Cashier', 'cashier', 'cashier@medistore.com', '+91-9876543211', '2026-03-14 10:36:18', '2026-03-14 10:36:18', 1);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_available_batches`
-- (See below for the actual view)
--
CREATE TABLE `vw_available_batches` (
`batch_id` int(11)
,`product_id` int(11)
,`product_name` varchar(200)
,`manufacturer` varchar(100)
,`price` decimal(10,2)
,`batch_number` varchar(50)
,`available_quantity` int(11)
,`expiry_date` date
,`days_until_expiry` int(7)
,`shelf_location` varchar(50)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_expired_batches`
-- (See below for the actual view)
--
CREATE TABLE `vw_expired_batches` (
`batch_id` int(11)
,`batch_number` varchar(50)
,`product_id` int(11)
,`product_name` varchar(200)
,`quantity` int(11)
,`expiry_date` date
,`days_past` int(7)
,`shelf_location` varchar(50)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_expiring_batches`
-- (See below for the actual view)
--
CREATE TABLE `vw_expiring_batches` (
`batch_id` int(11)
,`batch_number` varchar(50)
,`product_id` int(11)
,`product_name` varchar(200)
,`quantity` int(11)
,`expiry_date` date
,`days_left` int(7)
,`shelf_location` varchar(50)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `vw_product_stock`
-- (See below for the actual view)
--
CREATE TABLE `vw_product_stock` (
`product_id` int(11)
,`name` varchar(200)
,`manufacturer` varchar(100)
,`price` decimal(10,2)
,`total_stock` decimal(32,0)
,`batch_count` bigint(21)
,`nearest_expiry` date
,`min_stock_level` int(11)
);

-- --------------------------------------------------------

--
-- Structure for view `customer_purchase_summary`
--
DROP TABLE IF EXISTS `customer_purchase_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `customer_purchase_summary`  AS SELECT `c`.`id` AS `customer_id`, `c`.`name` AS `customer_name`, `c`.`phone` AS `phone`, count(distinct `b`.`id`) AS `total_purchases`, sum(`b`.`total_amount`) AS `total_spent`, max(`b`.`bill_date`) AS `last_purchase_date`, count(distinct `bi`.`medicine_name`) AS `unique_medicines_purchased` FROM ((`customers` `c` left join `bills` `b` on(`c`.`id` = `b`.`customer_id`)) left join `bill_items` `bi` on(`b`.`id` = `bi`.`bill_id`)) GROUP BY `c`.`id`, `c`.`name`, `c`.`phone` ;

-- --------------------------------------------------------

--
-- Structure for view `low_stock_items`
--
DROP TABLE IF EXISTS `low_stock_items`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `low_stock_items`  AS SELECT `p`.`id` AS `id`, `p`.`name` AS `name`, `p`.`manufacturer` AS `manufacturer`, `p`.`stock_quantity` AS `stock_quantity`, `p`.`min_stock_level` AS `min_stock_level`, `p`.`price` AS `price`, `p`.`category` AS `category`, `p`.`shelf_location` AS `shelf_location`, `p`.`min_stock_level`- `p`.`stock_quantity` AS `shortage_quantity` FROM `products` AS `p` WHERE `p`.`stock_quantity` < `p`.`min_stock_level` ORDER BY `p`.`stock_quantity` ASC ;

-- --------------------------------------------------------

--
-- Structure for view `sales_summary`
--
DROP TABLE IF EXISTS `sales_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `sales_summary`  AS SELECT cast(`b`.`bill_date` as date) AS `sale_date`, count(distinct `b`.`id`) AS `total_bills`, count(`bi`.`id`) AS `total_items_sold`, sum(`bi`.`quantity`) AS `total_quantity`, sum(`b`.`subtotal`) AS `total_subtotal`, sum(`b`.`gst`) AS `total_gst`, sum(`b`.`total_amount`) AS `total_revenue` FROM (`bills` `b` left join `bill_items` `bi` on(`b`.`id` = `bi`.`bill_id`)) GROUP BY cast(`b`.`bill_date` as date) ;

-- --------------------------------------------------------

--
-- Structure for view `supplier_purchase_summary`
--
DROP TABLE IF EXISTS `supplier_purchase_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `supplier_purchase_summary`  AS SELECT `s`.`id` AS `supplier_id`, `s`.`name` AS `supplier_name`, `s`.`company_name` AS `company_name`, count(`sp`.`id`) AS `total_orders`, sum(case when `sp`.`status` = 'to_be_ordered' then 1 else 0 end) AS `pending_orders`, sum(case when `sp`.`status` = 'ordered' then 1 else 0 end) AS `ordered_count`, sum(case when `sp`.`status` = 'received' then 1 else 0 end) AS `received_count`, sum(case when `sp`.`status` = 'received' then `sp`.`total_amount` else 0 end) AS `total_purchase_value` FROM (`suppliers` `s` left join `supplier_purchases` `sp` on(`s`.`id` = `sp`.`supplier_id`)) GROUP BY `s`.`id`, `s`.`name`, `s`.`company_name` ;

-- --------------------------------------------------------

--
-- Structure for view `top_selling_products`
--
DROP TABLE IF EXISTS `top_selling_products`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `top_selling_products`  AS SELECT `bi`.`medicine_name` AS `medicine_name`, `bi`.`product_id` AS `product_id`, count(distinct `bi`.`bill_id`) AS `times_sold`, sum(`bi`.`quantity`) AS `total_quantity_sold`, sum(`bi`.`total_amount`) AS `total_revenue`, avg(`bi`.`price`) AS `average_price` FROM `bill_items` AS `bi` GROUP BY `bi`.`medicine_name`, `bi`.`product_id` ORDER BY sum(`bi`.`quantity`) DESC ;

-- --------------------------------------------------------

--
-- Structure for view `vw_available_batches`
--
DROP TABLE IF EXISTS `vw_available_batches`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_available_batches`  AS SELECT `pb`.`id` AS `batch_id`, `pb`.`product_id` AS `product_id`, `p`.`name` AS `product_name`, `p`.`manufacturer` AS `manufacturer`, `p`.`price` AS `price`, `pb`.`batch_number` AS `batch_number`, `pb`.`quantity` AS `available_quantity`, `pb`.`expiry_date` AS `expiry_date`, to_days(`pb`.`expiry_date`) - to_days(curdate()) AS `days_until_expiry`, `pb`.`shelf_location` AS `shelf_location` FROM (`product_batches` `pb` join `products` `p` on(`pb`.`product_id` = `p`.`id`)) WHERE `pb`.`quantity` > 0 AND (`pb`.`expiry_date` is null OR `pb`.`expiry_date` > curdate()) ORDER BY `pb`.`product_id` ASC, `pb`.`expiry_date` ASC, `pb`.`quantity` ASC ;

-- --------------------------------------------------------

--
-- Structure for view `vw_expired_batches`
--
DROP TABLE IF EXISTS `vw_expired_batches`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_expired_batches`  AS SELECT `pb`.`id` AS `batch_id`, `pb`.`batch_number` AS `batch_number`, `p`.`id` AS `product_id`, `p`.`name` AS `product_name`, `pb`.`quantity` AS `quantity`, `pb`.`expiry_date` AS `expiry_date`, to_days(curdate()) - to_days(`pb`.`expiry_date`) AS `days_past`, `pb`.`shelf_location` AS `shelf_location` FROM (`product_batches` `pb` join `products` `p` on(`pb`.`product_id` = `p`.`id`)) WHERE `pb`.`expiry_date` is not null AND `pb`.`expiry_date` < curdate() AND `pb`.`quantity` > 0 ORDER BY `pb`.`expiry_date` DESC ;

-- --------------------------------------------------------

--
-- Structure for view `vw_expiring_batches`
--
DROP TABLE IF EXISTS `vw_expiring_batches`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_expiring_batches`  AS SELECT `pb`.`id` AS `batch_id`, `pb`.`batch_number` AS `batch_number`, `p`.`id` AS `product_id`, `p`.`name` AS `product_name`, `pb`.`quantity` AS `quantity`, `pb`.`expiry_date` AS `expiry_date`, to_days(`pb`.`expiry_date`) - to_days(curdate()) AS `days_left`, `pb`.`shelf_location` AS `shelf_location` FROM (`product_batches` `pb` join `products` `p` on(`pb`.`product_id` = `p`.`id`)) WHERE `pb`.`expiry_date` is not null AND `pb`.`expiry_date` > curdate() AND to_days(`pb`.`expiry_date`) - to_days(curdate()) <= 50 AND `pb`.`quantity` > 0 ORDER BY `pb`.`expiry_date` ASC ;

-- --------------------------------------------------------

--
-- Structure for view `vw_product_stock`
--
DROP TABLE IF EXISTS `vw_product_stock`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_product_stock`  AS SELECT `p`.`id` AS `product_id`, `p`.`name` AS `name`, `p`.`manufacturer` AS `manufacturer`, `p`.`price` AS `price`, coalesce(sum(`pb`.`quantity`),0) AS `total_stock`, count(`pb`.`id`) AS `batch_count`, min(`pb`.`expiry_date`) AS `nearest_expiry`, `p`.`min_stock_level` AS `min_stock_level` FROM (`products` `p` left join `product_batches` `pb` on(`p`.`id` = `pb`.`product_id` and `pb`.`quantity` > 0)) GROUP BY `p`.`id` ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `batch_bill_items`
--
ALTER TABLE `batch_bill_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_bill_id` (`bill_id`),
  ADD KEY `idx_batch_id` (`batch_id`);

--
-- Indexes for table `batch_transactions`
--
ALTER TABLE `batch_transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_batch_id` (`batch_id`),
  ADD KEY `idx_transaction_type` (`transaction_type`),
  ADD KEY `idx_transaction_date` (`transaction_date`),
  ADD KEY `created_by` (`created_by`);

--
-- Indexes for table `bills`
--
ALTER TABLE `bills`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `bill_number` (`bill_number`),
  ADD KEY `idx_bill_number` (`bill_number`),
  ADD KEY `idx_customer_id` (`customer_id`),
  ADD KEY `idx_bill_date` (`bill_date`),
  ADD KEY `idx_customer_name` (`customer_name`),
  ADD KEY `idx_payment_status` (`payment_status`),
  ADD KEY `idx_payment_method` (`payment_method`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `payment_approved_by` (`payment_approved_by`),
  ADD KEY `idx_bills_customer_date` (`customer_id`,`bill_date`);

--
-- Indexes for table `bill_items`
--
ALTER TABLE `bill_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_bill_id` (`bill_id`),
  ADD KEY `idx_product_id` (`product_id`),
  ADD KEY `idx_medicine_name` (`medicine_name`),
  ADD KEY `idx_bill_items_medicine` (`medicine_name`,`bill_id`);

--
-- Indexes for table `customers`
--
ALTER TABLE `customers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `phone` (`phone`),
  ADD KEY `idx_phone` (`phone`),
  ADD KEY `idx_name` (`name`);

--
-- Indexes for table `pending_orders`
--
ALTER TABLE `pending_orders`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `order_number` (`order_number`),
  ADD KEY `idx_order_number` (`order_number`),
  ADD KEY `idx_customer_id` (`customer_id`),
  ADD KEY `idx_payment_status` (`payment_status`),
  ADD KEY `idx_created_at` (`created_at`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `approved_by` (`approved_by`);

--
-- Indexes for table `products`
--
ALTER TABLE `products`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_name` (`name`),
  ADD KEY `idx_manufacturer` (`manufacturer`),
  ADD KEY `idx_category` (`category`),
  ADD KEY `idx_stock_low` (`stock_quantity`,`min_stock_level`),
  ADD KEY `idx_products_stock_name` (`stock_quantity`,`name`);
ALTER TABLE `products` ADD FULLTEXT KEY `idx_search` (`name`,`manufacturer`,`category`);

--
-- Indexes for table `product_batches`
--
ALTER TABLE `product_batches`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_batch` (`product_id`,`batch_number`),
  ADD KEY `idx_product_id` (`product_id`),
  ADD KEY `idx_expiry_date` (`expiry_date`),
  ADD KEY `idx_batch_number` (`batch_number`),
  ADD KEY `idx_quantity` (`quantity`),
  ADD KEY `supplier_id` (`supplier_id`);

--
-- Indexes for table `regular_purchases`
--
ALTER TABLE `regular_purchases`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_customer_product` (`customer_id`,`product_id`),
  ADD KEY `idx_customer_id` (`customer_id`),
  ADD KEY `idx_product_id` (`product_id`);

--
-- Indexes for table `returns`
--
ALTER TABLE `returns`
  ADD PRIMARY KEY (`id`),
  ADD KEY `bill_id` (`bill_id`),
  ADD KEY `product_id` (`product_id`),
  ADD KEY `processed_by` (`processed_by`);

--
-- Indexes for table `settings`
--
ALTER TABLE `settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `setting_key` (`setting_key`),
  ADD KEY `idx_setting_key` (`setting_key`);

--
-- Indexes for table `suppliers`
--
ALTER TABLE `suppliers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `phone` (`phone`),
  ADD KEY `idx_name` (`name`),
  ADD KEY `idx_phone` (`phone`);

--
-- Indexes for table `supplier_purchases`
--
ALTER TABLE `supplier_purchases`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `purchase_number` (`purchase_number`),
  ADD KEY `idx_purchase_number` (`purchase_number`),
  ADD KEY `idx_supplier_id` (`supplier_id`),
  ADD KEY `idx_product_id` (`product_id`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_order_date` (`order_date`),
  ADD KEY `idx_supplier_purchases_status_date` (`status`,`order_date`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD UNIQUE KEY `email` (`email`),
  ADD UNIQUE KEY `phone` (`phone`),
  ADD KEY `idx_username` (`username`),
  ADD KEY `idx_role` (`role`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `batch_bill_items`
--
ALTER TABLE `batch_bill_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `batch_transactions`
--
ALTER TABLE `batch_transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `bills`
--
ALTER TABLE `bills`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=103;

--
-- AUTO_INCREMENT for table `bill_items`
--
ALTER TABLE `bill_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=210;

--
-- AUTO_INCREMENT for table `customers`
--
ALTER TABLE `customers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=80;

--
-- AUTO_INCREMENT for table `pending_orders`
--
ALTER TABLE `pending_orders`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `products`
--
ALTER TABLE `products`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=121;

--
-- AUTO_INCREMENT for table `product_batches`
--
ALTER TABLE `product_batches`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=126;

--
-- AUTO_INCREMENT for table `regular_purchases`
--
ALTER TABLE `regular_purchases`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `returns`
--
ALTER TABLE `returns`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `settings`
--
ALTER TABLE `settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;

--
-- AUTO_INCREMENT for table `suppliers`
--
ALTER TABLE `suppliers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `supplier_purchases`
--
ALTER TABLE `supplier_purchases`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `batch_bill_items`
--
ALTER TABLE `batch_bill_items`
  ADD CONSTRAINT `batch_bill_items_ibfk_1` FOREIGN KEY (`bill_id`) REFERENCES `bills` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `batch_bill_items_ibfk_2` FOREIGN KEY (`batch_id`) REFERENCES `product_batches` (`id`);

--
-- Constraints for table `batch_transactions`
--
ALTER TABLE `batch_transactions`
  ADD CONSTRAINT `batch_transactions_ibfk_1` FOREIGN KEY (`batch_id`) REFERENCES `product_batches` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `batch_transactions_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `bills`
--
ALTER TABLE `bills`
  ADD CONSTRAINT `bills_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `bills_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `bills_ibfk_3` FOREIGN KEY (`payment_approved_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `bill_items`
--
ALTER TABLE `bill_items`
  ADD CONSTRAINT `bill_items_ibfk_1` FOREIGN KEY (`bill_id`) REFERENCES `bills` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `bill_items_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `pending_orders`
--
ALTER TABLE `pending_orders`
  ADD CONSTRAINT `pending_orders_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `pending_orders_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `pending_orders_ibfk_3` FOREIGN KEY (`approved_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `product_batches`
--
ALTER TABLE `product_batches`
  ADD CONSTRAINT `product_batches_ibfk_1` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `product_batches_ibfk_2` FOREIGN KEY (`supplier_id`) REFERENCES `suppliers` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `regular_purchases`
--
ALTER TABLE `regular_purchases`
  ADD CONSTRAINT `regular_purchases_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `regular_purchases_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `returns`
--
ALTER TABLE `returns`
  ADD CONSTRAINT `returns_ibfk_1` FOREIGN KEY (`bill_id`) REFERENCES `bills` (`id`),
  ADD CONSTRAINT `returns_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`),
  ADD CONSTRAINT `returns_ibfk_3` FOREIGN KEY (`processed_by`) REFERENCES `users` (`id`);

--
-- Constraints for table `supplier_purchases`
--
ALTER TABLE `supplier_purchases`
  ADD CONSTRAINT `supplier_purchases_ibfk_1` FOREIGN KEY (`supplier_id`) REFERENCES `suppliers` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `supplier_purchases_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE SET NULL;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
