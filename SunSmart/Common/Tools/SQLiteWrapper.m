//
//  SQLiteWrapper.m
//  doodoModel
//
//  Created by Atem on 16/3/14.
//  Copyright © 2016年 HENGCHAT. All rights reserved.
//

#import "SQLiteWrapper.h"

@implementation SQLiteWrapper
{
    sqlite3 *db;//数据库句柄，跟文件句柄FILE很类似
    sqlite3_stmt *stmt;//这个相当于ODBC的Command对象，用于保存编译好的SQL语句
}

#pragma mark - Singleton

/**
 *  单例
 */
+ (instancetype)sharedSQLiteWrapper {
    
    static dispatch_once_t onceToken;
    static SQLiteWrapper *manager = nil;
    
    dispatch_once(&onceToken, ^{
        manager = [[SQLiteWrapper alloc] init];
    });
    return manager;
}


#pragma mark - Public Methods

- (BOOL)openDb:(NSString *)dbName{
    sqlite3_shutdown();
    sqlite3_config(SQLITE_CONFIG_SERIALIZED);
   
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = [documentPaths objectAtIndex:0];
    const char *databasePath = nil;
    if ([dbName containsString:documentsDir]) {
        databasePath = [dbName UTF8String];
    } else {
        databasePath = [[documentsDir stringByAppendingPathComponent:dbName] UTF8String];
    }
    
//    NSLog(@"databasePath %s",databasePath);
//    NSString *documentsDir = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.com.HC.biztalk"] absoluteString];
//    const char *databasePath = [[documentsDir stringByAppendingPathComponent:dbName] UTF8String];
    
    BOOL result = (sqlite3_open(databasePath, &db) == SQLITE_OK);
    if (!result) {
        NSLog(@"打开数据库失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)closeDb{
    BOOL result = (sqlite3_close(db) == SQLITE_OK);
    if (!result) {
        NSLog(@"关闭数据库失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)prepareSql:(const char *)sql{
    BOOL result = (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK);
    if (!result) {
        NSLog(@"准备执行 SQL 失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)stepSqlDone{
    BOOL result = (sqlite3_step(stmt) == SQLITE_DONE);
    if (!result) {
        NSLog(@"数据更新失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)stepSqlRow{
    BOOL result = (sqlite3_step(stmt) == SQLITE_ROW);
    return result;
}

- (NSString *)columnText:(int)col{
    NSString *result = @"";
    char *charResult = (char*)sqlite3_column_text(stmt, col);
    if(charResult != nil){
        result = [[NSString alloc]initWithUTF8String:charResult];
    }
    return result;
}

- (BOOL)columnBool:(int)col{
    BOOL result = NO;
    char *charResult = (char*)sqlite3_column_text(stmt, col);
    if(charResult != nil){
        NSString *strResult = [[NSString alloc]initWithUTF8String:charResult];
        if ([strResult isEqualToString:@"1"]) {
            result = YES;
        }
    }
    return result;
}

- (int)columnInt:(int)col{
    return sqlite3_column_int(stmt, col);
}

- (NSData *)columnBlob:(int)col{
    NSData *result = nil;
    char *charResult = (char *)sqlite3_column_blob(stmt, col);
    if(charResult != nil){
        result = [NSData dataWithBytes:charResult length:sqlite3_column_bytes(stmt, col)];
    }
    return result;
}

- (NSDate *)columnDate:(int)col{
    NSDate *result = nil;
    char *charResult = (char*)sqlite3_column_text(stmt, col);
    if(charResult != nil && charResult!=0){
        NSString *resultStr = [[NSString alloc]initWithUTF8String:charResult];
        NSLog(@"时间1 %@",resultStr);
        if (![resultStr isEqualToString:@"0"]) {
            NSLog(@"时间2 %@",resultStr);
            result =[[NSDate alloc] initWithTimeIntervalSince1970:resultStr.doubleValue];
        }
    }
    return result;
}

- (BOOL)bindText:(int)col text:(NSString *)text{
    const char *charText = [text cStringUsingEncoding:NSUTF8StringEncoding];
    BOOL result = (sqlite3_bind_text(stmt, col, charText, -1, SQLITE_STATIC) == SQLITE_OK);
    
    if (!result) {
        NSLog(@"绑定参数失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)bindBool:(int)col boolean:(BOOL)boolean {
    const char *charText = boolean?"1":"0";
    BOOL result = (sqlite3_bind_text(stmt, col, charText, -1, SQLITE_STATIC) == SQLITE_OK);
    if (!result) {
        NSLog(@"绑定参数失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)bindDate:(int)col timestamp:(NSDate *)timestamp{
    NSTimeInterval time = [timestamp timeIntervalSince1970];
    BOOL result = (sqlite3_bind_double(stmt, col, time) == SQLITE_OK);
    if (!result) {
        NSLog(@"绑定参数失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)bindInt:(int)col integer:(sqlite3_int64)integer{
    BOOL result = (sqlite3_bind_int64(stmt, col, integer) == SQLITE_OK);
    if (!result) {
        NSLog(@"绑定参数失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)bindBlob:(int)col blob:(NSData *)blob{
    const char *charBlob = nil;
    if (blob == nil || [blob length] <=0) {
//        UIImage *defaultImage = [UIImage imageNamed:@"head"];
//        blob = UIImageJPEGRepresentation(defaultImage, 1.0f);
    }
    charBlob = [blob bytes];
    int blobLen = (int)blob.length;
    BOOL result = (sqlite3_bind_blob(stmt, col, charBlob, blobLen, SQLITE_STATIC) == SQLITE_OK);
    if (!result) {
        NSLog(@"绑定参数失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)resetSql{
    BOOL result = (sqlite3_reset(stmt) == SQLITE_OK);
    if (!result) {
        NSLog(@"重置声明失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)finalizeSql{
    BOOL result = (sqlite3_finalize(stmt) == SQLITE_OK);
    if (!result) {
        NSLog(@"释放声明失败，错误原因:%s", sqlite3_errmsg(db));
    }
    return result;
}

- (BOOL)execSql:(NSString *)sql{
    char *errorMsg;
    if (sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errorMsg) != SQLITE_OK) {
        NSLog(@"数据库操作数据失败，错误原因:%s\n", errorMsg);
        return NO;
    }
    sqlite3_free(errorMsg);
    return YES;
}

- (BOOL)beginTransaction{
    char *errorMsg;
    int result = sqlite3_exec(db, "BEGIN TRANSACTION", NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        NSLog(@"开始事务记录失败，错误原因:%s\n", errorMsg);
    }
    sqlite3_free(errorMsg);
    return result == 0;
}

- (BOOL)commitTransaction{
    char *errorMsg;
    int result = sqlite3_exec(db, "COMMIT TRANSACTION", NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        NSLog(@"提交事务记录失败，错误原因:%s\n", errorMsg);
    }
    sqlite3_free(errorMsg);
    return result == 0;
}

- (BOOL)rollbackTransaction{
    char *errorMsg;
    int result = sqlite3_exec(db, "ROLLBACK TRANSACTION", NULL, NULL, &errorMsg);
    if (result != SQLITE_OK) {
        NSLog(@"回滚事务记录失败，错误原因:%s\n", errorMsg);
    }
    sqlite3_free(errorMsg);
    return result == 0;
}

///检查是表中是否有某个字段
-(BOOL)checkHaveTableName:(NSString *)tableName column:(NSString *)column{
//    sqlite3 *db = [DBDatebase open];
    NSString *sql = [NSString stringWithFormat:@"select * from sqlite_master where name='%@' and sql like '%%%@%%'",tableName,column];
//           NSString * sql = @"select * from sqlite_master where name='user' and sql like '%enterPrisede%'";
    //查询的句柄,游标
    sqlite3_stmt * stmt;
    NSMutableArray *mArray = [NSMutableArray array];
    
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        //查询数据
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            //获取查询了多少列
            int count = sqlite3_column_count(stmt);
            //创建字典
            NSMutableDictionary *dic = [NSMutableDictionary dictionary];
            
            for (int i = 0; i<count; i++) {
                //如果是text类型
                int column_type = sqlite3_column_type(stmt, i);
                NSString *column_name = [NSString stringWithUTF8String:sqlite3_column_name(stmt,i)];
                if (column_type == SQLITE_TEXT) {
                    [dic setValue:[NSString stringWithUTF8String:(char *)sqlite3_column_text(stmt, i)] forKeyPath:column_name];
                }
                if (column_type == SQLITE_INTEGER) {
                    [NSString stringWithFormat:@"%d",sqlite3_column_int(stmt, i)];
                    [dic setValue:[NSString stringWithFormat:@"%d",sqlite3_column_int(stmt, i)] forKeyPath:column_name];
                }
                if (column_type == SQLITE_NULL) {
                    [dic setValue:@"" forKeyPath:column_name];
                }
            }
            [mArray addObject:dic];
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    if (mArray.count) {
        return YES;
    }else{
        return NO;
    }
}


@end
