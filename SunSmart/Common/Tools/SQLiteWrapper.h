//
//  SQLiteWrapper.h
//  doodoModel
//
//  Created by Atem on 16/3/14.
//  Copyright © 2016年 HENGCHAT. All rights reserved.
//

#import <Foundation/Foundation.h>

//doodo
//#import "Stylesheet.h"

#import <sqlite3.h>

@interface SQLiteWrapper : NSObject

@property(nonatomic, assign)BOOL isOpen;

/**
 *  单例
 */
+ (instancetype)sharedSQLiteWrapper;

- (BOOL)openDb:(NSString *)dbName;

- (BOOL)closeDb;

- (BOOL)prepareSql:(const char *)sql;

- (BOOL)stepSqlDone;

- (BOOL)stepSqlRow;

- (NSString *)columnText:(int)col;

- (BOOL)columnBool:(int)col;

- (int)columnInt:(int)col;

- (long long)columnInt64:(int)col;

- (NSData *)columnBlob:(int)col;

- (NSDate *)columnDate:(int)col;

- (BOOL)bindText:(int)col text:(NSString *)text;

- (BOOL)bindBool:(int)col boolean:(BOOL)boolean;

- (BOOL)bindDate:(int)col timestamp:(NSDate *)timestamp;

- (BOOL)bindInt:(int)col integer:(sqlite3_int64)integer;

- (BOOL)bindBlob:(int)col blob:(NSData *)blob;

- (BOOL)resetSql;

- (BOOL)finalizeSql;

- (BOOL)execSql:(NSString *)sql;

- (BOOL)beginTransaction;

- (BOOL)commitTransaction;

- (BOOL)rollbackTransaction;

///检查是表中是否有某个字段
-(BOOL)checkHaveTableName:(NSString *)tableName column:(NSString *)column;

@end
