//
// --------------------------------------------------------------------------
// OverridePanel.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2020
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

#import "OverridePanel.h"
#import "Config.h"
#import "Utility_App.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Mac_Mouse_Fix-Swift.h"

@interface OverridePanel ()

@property (strong) IBOutlet NSTableView *tableView;

@end

@implementation OverridePanel {
    NSMutableArray<NSMutableDictionary *> *_tableViewDataModel;
    BOOL _didConfigureInterface;
}

#pragma mark - Class

+ (void)load {
    _instance = [[OverridePanel alloc] initWithWindowNibName:@"ScrollOverridePanel"];
}

static OverridePanel *_instance;
+ (OverridePanel *)instance {
    return _instance;
}

#pragma mark - Lifecycle

- (void)windowDidLoad {
    [super windowDidLoad];
    [self configureInterfaceIfNeeded];
}

- (void)begin {
    
    (void)self.window; /// Force nib load.
    [self configureInterfaceIfNeeded];
    [self loadTableViewDataModelFromConfig];
    [self.tableView reloadData];
    
    [self centerWindowOnMainWindow];
    self.window.level = NSFloatingWindowLevel;
    self.window.styleMask = self.window.styleMask | NSWindowStyleMaskResizable;
    [self.window standardWindowButton:NSWindowCloseButton].hidden = YES;
    [self.window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [self.window standardWindowButton:NSWindowZoomButton].hidden = YES;
    
    [Utility_App openWindowWithFadeAnimation:self.window fadeIn:YES fadeTime:0.1];
}

- (void)end {
    if (self.window.isVisible) {
        [Utility_App openWindowWithFadeAnimation:self.window fadeIn:NO fadeTime:0.1];
    }
}

- (void)configureInterfaceIfNeeded {
    
    if (_didConfigureInterface) {
        return;
    }
    
    _didConfigureInterface = YES;
    
    self.window.title = @"Scrolling Apps";
    
    NSString *fileURLUTI = @"public.file-url";
    [self.tableView registerForDraggedTypes:@[fileURLUTI]];
    self.tableView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    
    NSTableColumn *appColumn = [self.tableView tableColumnWithIdentifier:@"AppColumnID"];
    appColumn.headerCell.title = @"Apps";
    appColumn.headerToolTip = @"Add apps here to use them in the scrolling app filter";
    
    NSArray<NSTableColumn *> *columns = self.tableView.tableColumns.copy;
    for (NSTableColumn *column in columns) {
        if (![column.identifier isEqualToString:@"AppColumnID"]) {
            [self.tableView removeTableColumn:column];
        }
    }
}

- (void)centerWindowOnMainWindow {
    NSPoint ctr = [Utility_App getCenterOfRect:MainAppState.shared.window.frame];
    [Utility_App centerWindow:self.window atPoint:ctr];
}

#pragma mark - Actions

- (IBAction)back:(id)sender {
    [self end];
}

- (IBAction)addRemoveControl:(id)sender {
    if ([sender selectedSegment] == 0) {
        [self addButtonAction];
    } else {
        [self removeButtonAction];
    }
}

- (IBAction)removeButton:(id)sender {
    [self removeButtonAction];
}

- (void)addButtonAction {
    
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.canCreateDirectories = NO;
    openPanel.allowsMultipleSelection = YES;
    if (@available(macOS 13.0, *)) {
        openPanel.allowedContentTypes = @[[UTType typeWithIdentifier:@"com.apple.application"]];
    } else {
        openPanel.allowedFileTypes = @[@"com.apple.application"];
    }
    openPanel.prompt = @"Choose";
    
    NSString *applicationsFolderPath = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSLocalDomainMask, YES).firstObject;
    openPanel.directoryURL = [NSURL fileURLWithPath:applicationsFolderPath];
    
    [openPanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            return;
        }
        
        NSMutableArray<NSString *> *bundleIDs = [NSMutableArray array];
        for (NSURL *fileURL in openPanel.URLs) {
            NSString *bundleID = [NSBundle bundleWithURL:fileURL].bundleIdentifier;
            if (bundleID != nil) {
                [bundleIDs addObject:bundleID];
            }
        }
        [self addAppsToTableWithBundleIDs:bundleIDs atRow:0];
    }];
}

- (void)removeButtonAction {
    
    NSIndexSet *selectedRows = self.tableView.selectedRowIndexes;
    if (selectedRows.count == 0) {
        return;
    }
    
    [_tableViewDataModel removeObjectsAtIndexes:selectedRows];
    [self writeTableViewDataModelToConfig];
    [self loadTableViewDataModelFromConfig];
    [self.tableView removeRowsAtIndexes:selectedRows withAnimation:NSTableViewAnimationSlideUp];
}

#pragma mark - Table view

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _tableViewDataModel.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    
    if (row >= _tableViewDataModel.count) {
        return nil;
    }
    
    if (![tableColumn.identifier isEqualToString:@"AppColumnID"]) {
        return nil;
    }
    
    NSTableCellView *appCell = [tableView makeViewWithIdentifier:@"AppCellID" owner:nil];
    if (appCell == nil) {
        return nil;
    }
    
    NSString *bundleID = _tableViewDataModel[row][@"AppColumnID"];
    NSString *appPath = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundleID].path;
    NSImage *appIcon = [NSImage imageNamed:NSImageNameApplicationIcon];
    NSString *appName = bundleID;
    
    if (appPath != nil) {
        appIcon = [NSWorkspace.sharedWorkspace iconForFile:appPath];
        appName = [[NSBundle bundleWithPath:appPath] objectForInfoDictionaryKey:@"CFBundleName"];
        if (appName == nil) {
            appName = [[NSURL fileURLWithPath:appPath] URLByDeletingPathExtension].lastPathComponent;
        }
    }
    
    appCell.textField.stringValue = appName ?: bundleID;
    appCell.textField.toolTip = bundleID;
    appCell.imageView.image = appIcon;
    return appCell;
}

#pragma mark - Drag and drop

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    
    NSPasteboard *pasteboard = info.draggingPasteboard;
    BOOL droppingAbove = (dropOperation == NSTableViewDropAbove);
    
    BOOL containsURL = [pasteboard.types containsObject:@"public.file-url"];
    NSDictionary *options = @{ NSPasteboardURLReadingContentsConformToTypesKey : @[@"com.apple.application-bundle"] };
    BOOL containsApp = [pasteboard canReadObjectForClasses:@[NSURL.self] options:options];
    NSArray<NSString *> *draggedBundleIDs = bundleIDsFromPasteboard(pasteboard);
    if (draggedBundleIDs.count == 0) {
        containsApp = NO;
    }
    
    NSDictionary *draggedBundleIDsSorted = sortByAlreadyInTable(draggedBundleIDs, _tableViewDataModel);
    BOOL allAppsAlreadyInTable = (((NSArray *)draggedBundleIDsSorted[@"notInTable"]).count == 0);
    NSMutableArray *tableIndicesOfAlreadyInTable = [((NSArray *)draggedBundleIDsSorted[@"inTable"]) valueForKey:@"tableIndex"];
    
    if (droppingAbove && containsURL && containsApp && !allAppsAlreadyInTable) {
        return NSDragOperationCopy;
    }
    if (!containsApp) {
        [NSCursor.operationNotAllowedCursor push];
    } else if (allAppsAlreadyInTable && tableIndicesOfAlreadyInTable.count > 0) {
        NSMutableIndexSet *indexSet = indexSetFromIndexArray(tableIndicesOfAlreadyInTable);
        [self.tableView selectRowIndexes:indexSet byExtendingSelection:NO];
        [self.tableView scrollRowToVisible:((NSNumber *)tableIndicesOfAlreadyInTable[0]).integerValue];
    }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    
    NSArray *items = info.draggingPasteboard.pasteboardItems;
    if (items.count == 0) {
        return false;
    }
    
    NSArray<NSString *> *bundleIDs = bundleIDsFromPasteboard(info.draggingPasteboard);
    [self addAppsToTableWithBundleIDs:bundleIDs atRow:0];
    
    [self.window makeKeyWindow];
    return true;
}

- (void)addAppsToTableWithBundleIDs:(NSArray<NSString *> *)bundleIDs atRow:(NSInteger)row {
    
    bundleIDs = [bundleIDs valueForKeyPath:@"@distinctUnionOfObjects.self"];
    NSDictionary *bundleIDsSorted = sortByAlreadyInTable(bundleIDs, _tableViewDataModel);
    
    NSMutableArray<NSMutableDictionary *> *newRows = [NSMutableArray array];
    for (NSString *bundleID in bundleIDsSorted[@"notInTable"]) {
        [newRows addObject:[@{ @"AppColumnID": bundleID } mutableCopy]];
    }
    
    NSIndexSet *newRowsIndices = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(row, newRows.count)];
    NSIndexSet *alreadyInTableRowsIndices = indexSetFromIndexArray([((NSArray *)bundleIDsSorted[@"inTable"]) valueForKey:@"tableIndex"]);
    
    [self.tableView selectRowIndexes:alreadyInTableRowsIndices byExtendingSelection:NO];
    
    [_tableViewDataModel insertObjects:newRows atIndexes:newRowsIndices];
    [self writeTableViewDataModelToConfig];
    [self loadTableViewDataModelFromConfig];
    [self.tableView insertRowsAtIndexes:newRowsIndices withAnimation:NSTableViewAnimationSlideDown];
    [self.tableView selectRowIndexes:newRowsIndices byExtendingSelection:YES];
    
    if (newRowsIndices.count > 0) {
        [self.tableView scrollRowToVisible:newRowsIndices.firstIndex];
    } else if (alreadyInTableRowsIndices.count > 0) {
        [self.tableView scrollRowToVisible:alreadyInTableRowsIndices.firstIndex];
    }
}

#pragma mark - Config sync

- (void)writeTableViewDataModelToConfig {
    NSArray<NSString *> *bundleIDs = [_tableViewDataModel valueForKey:@"AppColumnID"] ?: @[];
    setConfig(@"Scroll.appFilter.bundleIDs", bundleIDs.copy);
    commitConfig();
}

- (void)loadTableViewDataModelFromConfig {
    
    _tableViewDataModel = [NSMutableArray array];
    
    NSArray *bundleIDsRaw = config(@"Scroll.appFilter.bundleIDs");
    if (![bundleIDsRaw isKindOfClass:NSArray.class]) {
        return;
    }
    
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id value in bundleIDsRaw) {
        if (![value isKindOfClass:NSString.class]) {
            continue;
        }
        
        NSString *bundleID = (NSString *)value;
        if ([seen containsObject:bundleID]) {
            continue;
        }
        [seen addObject:bundleID];
        
        if (![Utility_App appIsInstalled:bundleID]) {
            continue;
        }
        
        [_tableViewDataModel addObject:[@{ @"AppColumnID": bundleID } mutableCopy]];
    }
}

#pragma mark - Utility

static NSArray<NSString *> *bundleIDsFromPasteboard(NSPasteboard *pasteboard) {
    NSArray *items = pasteboard.pasteboardItems;
    NSMutableArray *bundleIDs = [NSMutableArray arrayWithCapacity:items.count];
    for (NSPasteboardItem *item in items) {
        NSString *urlString = [item stringForType:@"public.file-url"];
        NSURL *url = [NSURL URLWithString:urlString];
        NSString *bundleID = [[NSBundle bundleWithURL:url] bundleIdentifier];
        if (bundleID != nil) {
            [bundleIDs addObject:bundleID];
        }
    }
    return bundleIDs;
}

static NSDictionary *sortByAlreadyInTable(NSArray<NSString *> *bundleIDs, NSArray<NSDictionary *> *tableRows) {
    NSArray *bundleIDsFromTable = [tableRows valueForKey:@"AppColumnID"] ?: @[];
    NSMutableArray<NSString *> *notInTable = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *inTable = [NSMutableArray array];
    
    for (NSString *bundleID in bundleIDs) {
        NSUInteger tableIndex = [bundleIDsFromTable indexOfObject:bundleID];
        if (tableIndex != NSNotFound) {
            [inTable addObject:@{
                @"id": bundleID,
                @"tableIndex": @(tableIndex),
            }];
        } else {
            [notInTable addObject:bundleID];
        }
    }
    
    return @{
        @"inTable": inTable,
        @"notInTable": notInTable,
    };
}

static NSMutableIndexSet *indexSetFromIndexArray(NSArray<NSNumber *> *arrayOfIndices) {
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (NSNumber *index in arrayOfIndices) {
        [indexSet addIndex:index.unsignedIntegerValue];
    }
    return indexSet;
}

@end
