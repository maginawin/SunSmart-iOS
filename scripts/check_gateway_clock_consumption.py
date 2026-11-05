#!/usr/bin/env python3
"""Execute production click/preparation/rendering and result consumption without UIKit.

Only view primitives, table reload, Service responses and coordinator I/O are
test boundaries. Controller methods and the action-row binding are extracted.
"""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift').read_text()
def method(name):
 start=source.index('    private func '+name); end=source.index('{',start)+1; depth=1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end].replace('private func','func',1)
methods='\n'.join(method(n) for n in [
 'gatewayClockEnvironmentDidChange','scheduleGatewayClockSyncCompletion',
 'synchronizeGatewayClock','synchronizePreparedGatewayClock',
 'startGatewayClockSynchronization','readGatewayClock'])
if 'private func invalidateGatewayClockOperation' in source: methods+='\n'+method('invalidateGatewayClockOperation')
# Keep the production state-to-visible-row binding, including its click closure.
bindingStart=source.index('                cell.update(\n                    offBySeconds: gatewayClockState.offBySeconds,')
binding=source[bindingStart:source.index('\n                tableviewCell = cell',bindingStart)]
cellStart=source.index('private final class GatewayClockOffsetCell:')
savedSource=source; source=source[cellStart:].replace('@objc private func', 'private func')
cellMethods=method('updateSyncingAppearance')+'\n'+method('actionButtonTapped')
updateStart=source.index('    func update(')
cellMethods+='\n'+source[updateStart:source.index('    private func actionButtonTapped',updateStart)]
source=savedSource
siteSource=(root/'SunSmart/Main/Site/Controller/SiteViewController.swift').read_text()
savedSource=source; source=siteSource
siteMethod=method('recordGatewayDetailTimeZoneConfirmation')
source=savedSource
core=(root/'SunSmart/Main/Device/Gateway/Model/GatewayDetailClockCoordinator.swift').read_text().split('#if canImport')[0]
stub=r'''
import Foundation
extension String { var localizedString: String { self } }
enum GatewayDetailClockCoordinatorError: Error { case disconnected }
enum Section { case clock,timeZone }
typealias ClockResult = Result<(GatewayDetailClockSample, Int), GatewayDetailClockCoordinatorError>
class Coordinator {
 var syncStarts=0, readStarts=0
 var syncStartedAt: TimeInterval=0
 var readCompletion: ((ClockResult)->Void)?
 var syncCompletion: ((ClockResult)->Void)?
 func cancelForDeletion() {}
 func read(target: GatewayDetailTargetTimeZone, completion: @escaping (ClockResult)->Void) -> Bool { readStarts+=1; readCompletion=completion; return true }
 func synchronize(target: GatewayDetailTargetTimeZone, completion: @escaping (ClockResult)->Void) -> Bool { syncStarts+=1; syncStartedAt=ProcessInfo.processInfo.systemUptime; syncCompletion=completion; return true }
}
class Primitive {
 var isEnabled=true, isHidden=false
 var text: String?, accessibilityLabel: String?
 var backgroundColor=0
}
let Green_Color=1
func RGB(_ r: Int,_ g: Int,_ b: Int) -> Int { r+g+b }
class Cell {
 let actionButton=Primitive(), actionTitleLabel=Primitive(), loadingIconContainer=Primitive()
 let titleLabel=Primitive(), statusView=Primitive()
 var action: (()->Void)?
 var isShowingSyncing=false, animationRunning=false
 func startLoadingAnimation() { animationRunning=true }
 func stopLoadingAnimation() { animationRunning=false }
 CELL_METHODS
}
class WindowView { var window: Int?=1 }
class XWHUDManager { static var errors=0; static func showErrorTipHUD(_ message: String) { errors+=1 } }
@MainActor class SiteTimeZoneService {
 static let shared=SiteTimeZoneService()
 var requests: [CheckedContinuation<Int?,Never>]=[]
 func prepareClock(storageValue: String?) async -> Int? {
  assert(storageValue == "Asia/Singapore")
  return await withCheckedContinuation { requests.append($0) }
 }
 func finish(_ index: Int, success: Bool) { requests[index].resume(returning: success ? 1 : nil) }
}
class AutoPrompt { func request(sessionID: UUID, requiresSync: Bool) {} }
class ToastStatusView { enum Kind { case success,failure }; enum Appearance { case siteUpdate }; enum Position { case bottom }; static var successes=0, failures=0; static func show(in: Int,message: String,type: Kind,appearance: Appearance,position: Position) { if type == .success { successes+=1 } else { failures+=1 } } }
class Controller {
 var isViewVisible=true, showsGatewayClockSections=true, isGatewayClockReading=false, gatewayConnectionPageFinished=false
 var preparingGatewayDST=false
 var gatewayClockPreparationID: UUID?
 var gatewayClockCoordinator: Coordinator! = Coordinator()
 var pendingGatewayClockSync: (target: GatewayDetailTargetTimeZone,presentationID: UUID,startedAtUptime: TimeInterval)?
 var gatewayClockSyncPresentationID: UUID?
 var gatewayClockState=GatewayDetailClockState()
 var gatewayClockObservedTarget: GatewayDetailTargetTimeZone?
 var gatewayProxyReadySessionID: UUID? = UUID()
 var gatewayClockReadSessionID: UUID?
 var target=GatewayDetailTimeZoneResolver.resolve(storageValue: "Asia/Singapore")
 var reads: Int { gatewayClockCoordinator.readStarts }
 var published=0, reloads=0
 var isDeletingGateway=false
 var completedDeletionResetConfirmed: Bool?
 var site=(timezone: Optional("Asia/Singapore"), dummy: 0)
 var viewIfLoaded: WindowView?=WindowView()
 var gatewayClockAutoPromptState=AutoPrompt()
 let cell=Cell()
 var gateway=(mac: "gateway", dummy: 0)
 var view=0
 var timeZoneSyncDidFinish: ((String,Int)->Void)?
 func currentGatewayClockTarget() -> GatewayDetailTargetTimeZone { target }
 func isCurrentGatewayProxySession(_ id: UUID) -> Bool { id == gatewayProxyReadySessionID }
 func refreshGatewayDSTSummary() {}
 func reloadSection(_ section: Section) { if section == .clock { reloads+=1; render() } }
 func render() { CELL_BINDING }
 func markCurrentGatewayClockSessionHandled() {}
 func attemptGatewayClockAutoPrompt() {}
'''
stub=stub.replace('CELL_METHODS',cellMethods).replace('CELL_BINDING',binding)
tests=r'''
}
@main struct Tests { @MainActor static func main() async {
 SiteDSTFixtures.install()
 let c=Controller(); let old=c.target
 let sample=GatewayDetailClockSample(seconds: 100,subSecond: 0,taiDelta: 0,offsetMinutes: 480)
 c.gatewayClockObservedTarget=old
 c.gatewayClockState.accept(sample: sample,offBySeconds: 0,targetOffsetMinutes: 480)
 if CommandLine.arguments[1].hasPrefix("prepare-") {
  await verifyPreparation(c, sample: sample, mode: CommandLine.arguments[1])
 } else if CommandLine.arguments[1] == "system-time" {
  c.gatewayClockEnvironmentDidChange(forceRead: true)
  assert(c.reads == 1 && c.gatewayClockState.sample == nil, "system clock changes must re-sample even at identical offset")
 } else if CommandLine.arguments[1] == "busy" {
  c.gatewayClockState.beginSync(); c.isGatewayClockReading=true
  c.target=GatewayDetailTimeZoneResolver.resolve(storageValue: "Asia/Tokyo")
  c.gatewayClockEnvironmentDidChange()
  assert(c.gatewayClockState.offBySeconds == nil, "new Local must not consume old Off by")
  assert(!c.gatewayClockState.isSyncing && c.isGatewayClockReading && c.reads == 1,
         "invalidated sync must end and real read must start for the new target")
  c.gatewayClockEnvironmentDidChange(); assert(c.reads == 1, "same target notifications coalesce")
 } else {
  let id=UUID(); c.gatewayClockSyncPresentationID=id; c.gatewayClockState.beginSync()
  c.timeZoneSyncDidFinish={ _,_ in c.published+=1 }
  c.scheduleGatewayClockSyncCompletion(.success((sample,0)),target: old,presentationID:id,startedAtUptime: ProcessInfo.processInfo.systemUptime - 0.95)
  if CommandLine.arguments[1] == "delay-exit" { c.gatewayConnectionPageFinished=true; c.isViewVisible=false }
  else if CommandLine.arguments[1] == "delay-reconnect" { c.gatewayProxyReadySessionID=UUID() }
  else { c.target=GatewayDetailTimeZoneResolver.resolve(storageValue: "Asia/Tokyo") }
  try! await Task.sleep(nanoseconds: 150_000_000)
  assert(c.published == 0 && ToastStatusView.successes == 0, "delayed result must not confirm changed target")
  assert(!c.gatewayClockState.isSyncing, "stale completion must clear loading")
 }
 print("PASS controller \(CommandLine.arguments[1])")
} }
'''
siteFixture = r'''
struct SiteGatewayAccessScope { static func normalize(_ value: String) -> String? { value.lowercased() } }
class SiteConsumer {
 var gatewayDetailPresentationSessionID: UUID? = UUID()
 var site = (timezone: Optional("Asia/Singapore"), dummy: 0)
 var confirmedGatewayOffsetMinutesByID: [String:Int] = [:]
''' + siteMethod + r'''
 func verify() {
  let session = gatewayDetailPresentationSessionID!
  recordGatewayDetailTimeZoneConfirmation(gatewayID: "G", expectedGatewayID: "G", offsetMinutes: 480, sessionID: session)
  assert(confirmedGatewayOffsetMinutesByID["g"] == 480)
  confirmedGatewayOffsetMinutesByID = [:]
  for (id, offset, token) in [("wrong",480,session),("G",540,session),("G",480,UUID())] {
   recordGatewayDetailTimeZoneConfirmation(gatewayID:id, expectedGatewayID:"G", offsetMinutes:offset, sessionID:token)
  }
  assert(confirmedGatewayOffsetMinutesByID.isEmpty)
 }
}
'''
tests=tests.replace(' let c=Controller();', ' SiteConsumer().verify()\n let c=Controller();')
preparationTests=r'''
@MainActor func settle() async { try! await Task.sleep(nanoseconds: 20_000_000) }
@MainActor func waitFor(_ condition: ()->Bool) async {
 let deadline=Date().addingTimeInterval(2)
 while !condition() && Date() < deadline { await settle() }
 assert(condition(), "asynchronous boundary did not complete")
}
func expectLoading(_ c: Controller, _ expected: Bool) {
 assert(c.cell.isShowingSyncing == expected && c.cell.animationRunning == expected,
        "visible Sync clock loading must match operation ownership")
 assert(c.cell.actionButton.isEnabled == !expected && c.cell.loadingIconContainer.isHidden == !expected,
        "Sync clock must become enabled and hide spinner after preparation failure")
 assert(c.cell.actionTitleLabel.text == (expected ? "gateway_clock_syncing" : "gateway_sync_clock"))
}
@MainActor func verifyPreparation(_ c: Controller, sample: GatewayDetailClockSample, mode: String) async {
 let service=SiteTimeZoneService.shared
 // A valid Site with no usable cached snapshot: target is already observed,
 // so a failed refresh's unchanged Store notification cannot reset the row.
 SiteTimeZoneValue.snapshotProvider={ _,_ in nil }
 c.target=GatewayDetailTimeZoneResolver.resolve(storageValue: "Asia/Singapore")
 c.gatewayClockObservedTarget=c.target
 c.render()
 c.timeZoneSyncDidFinish={ _,_ in c.published+=1 }
 if mode == "prepare-pending" { c.readGatewayClock() }
 c.cell.actionButtonTapped()
 expectLoading(c,true)
 await waitFor { service.requests.count == 1 }
 let firstID=c.gatewayClockPreparationID
 c.cell.actionButtonTapped()
 assert(c.gatewayClockPreparationID == firstID && service.requests.count == 1,
        "disabled button must not start duplicate preparation")

 if mode == "prepare-fail" || mode == "prepare-fail-notify" || mode == "prepare-retry" {
  if mode == "prepare-fail-notify" {
   let reloads=c.reloads
   c.gatewayClockEnvironmentDidChange()
   assert(c.reloads == reloads && c.reads == 0, "same target notification must remain coalesced")
  }
  service.finish(0,success:false)
  await waitFor { !c.preparingGatewayDST }
  print("prepare_failed=true, preparing=\(c.preparingGatewayDST), button_enabled=\(c.cell.actionButton.isEnabled), cell_loading=\(c.cell.isShowingSyncing), sync_started=\(c.gatewayClockCoordinator.syncStarts)")
  expectLoading(c,false)
  assert(XWHUDManager.errors == 1 && c.gatewayClockCoordinator.syncStarts == 0 && c.published == 0)
  if mode != "prepare-retry" { return }
  c.cell.actionButtonTapped()
  await waitFor { service.requests.count == 2 }
  expectLoading(c,true)
  service.finish(1,success:true)
 } else if mode.hasPrefix("prepare-exit-") || mode.hasPrefix("prepare-disconnect-") || mode.hasPrefix("prepare-new-") {
  // Lifecycle transport is simulated; execute the production invalidation
  // method shared by finishGatewayConnectionSession and Proxy-not-ready.
  let exiting=mode.hasPrefix("prepare-exit-")
  c.gatewayConnectionPageFinished=exiting
  c.isViewVisible = !exiting
  c.gatewayProxyReadySessionID=nil
  c.invalidateGatewayClockOperation()
  c.reloadSection(.clock)
  expectLoading(c,false)
  let newer=mode.hasPrefix("prepare-new-")
  if newer {
   c.gatewayProxyReadySessionID=UUID()
   c.cell.actionButtonTapped()
   await waitFor { service.requests.count == 2 }
   if mode.hasPrefix("prepare-new-sync-") {
    service.finish(1,success:true)
    await waitFor { c.gatewayClockCoordinator.syncStarts == 1 }
   }
  }
  let newID=c.gatewayClockPreparationID, presentationID=c.gatewayClockSyncPresentationID
  let reloads=c.reloads, starts=c.gatewayClockCoordinator.syncStarts
  service.finish(0,success:mode.hasSuffix("success"))
  await settle()
  assert(c.reloads == reloads && c.gatewayClockPreparationID == newID && c.gatewayClockSyncPresentationID == presentationID,
         "stale preparation must not render or clear a newer operation")
  assert(XWHUDManager.errors == 0 && c.gatewayClockCoordinator.syncStarts == starts && c.published == 0)
  expectLoading(c,newer)
  if !newer { return }
  if !mode.hasPrefix("prepare-new-sync-") {
   service.finish(1,success:true)
  }
 } else if mode == "prepare-context-changed" {
  c.site.timezone="Asia/Tokyo"
  service.finish(0,success:false)
  await waitFor { !c.preparingGatewayDST }
  expectLoading(c,false)
  assert(XWHUDManager.errors == 0 && c.gatewayClockCoordinator.syncStarts == 0)
  return
 } else {
  service.finish(0,success:true)
 }
 await waitFor { !c.preparingGatewayDST }
 expectLoading(c,true)
 let presentationStartedAt=c.pendingGatewayClockSync?.startedAtUptime ?? c.gatewayClockCoordinator.syncStartedAt
 if mode == "prepare-pending" {
  assert(c.pendingGatewayClockSync != nil && c.gatewayClockCoordinator.syncStarts == 0,
         "click during read must queue sync")
  c.gatewayClockCoordinator.readCompletion?(.success((sample,0)))
  assert(c.pendingGatewayClockSync == nil)
 }
 await waitFor { c.gatewayClockCoordinator.syncStarts == 1 }
 expectLoading(c,true)
 let failure=mode == "prepare-sync-fail"
 c.gatewayClockCoordinator.syncCompletion?(failure ? .failure(.disconnected) : .success((sample,0)))
 expectLoading(c,true)
 assert(c.published == 0 && ToastStatusView.successes == 0, "success must wait for minimum presentation duration")
 await waitFor { !c.gatewayClockState.isSyncing }
 assert(ProcessInfo.processInfo.systemUptime - presentationStartedAt >= 0.9,
        "quick completion must retain the one-second Syncing presentation")
 expectLoading(c,false)
 assert(c.published == (failure ? 0 : 1) && ToastStatusView.successes == (failure ? 0 : 1))
 assert(ToastStatusView.failures == (failure ? 1 : 0))
}
'''
with tempfile.TemporaryDirectory(prefix='gateway-consumption-') as d:
 p=Path(d);(p/'Core.swift').write_text(core);(p/'Tests.swift').write_text(stub+methods+tests+siteFixture+preparationTests)
 sdk=(root/'.local-sdk/nordic-sig-mesh-sdk').resolve()
 subprocess.run(['swiftc','-parse-as-library',str(root/'SunSmart/Common/Data/SiteTimeZoneValue.swift'),str(root/'Tests/Site/SiteDSTFixtures.swift'),str(sdk/'Sources/NordicSigMeshSDK/MeshLib/Message/MeshTimeConversion.swift'),str(p/'Core.swift'),str(p/'Tests.swift'),'-o',str(p/'test')],check=True)
 failed=[]
 modes=['busy','delay','delay-exit','delay-reconnect','system-time',
        'prepare-fail','prepare-fail-notify','prepare-retry','prepare-pending',
        'prepare-sync-fail','prepare-context-changed']
 modes += ['prepare-'+event+'-'+result for event in ['exit','disconnect','new','new-sync'] for result in ['nil','success']]
 for mode in modes:
  r=subprocess.run([str(p/'test'),mode],capture_output=True,text=True)
  print(r.stdout if r.returncode==0 else mode+': '+r.stderr.splitlines()[0])
  if r.returncode:failed.append(mode)
 if failed:raise SystemExit('FAILED '+str(failed))
