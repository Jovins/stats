//
//  main.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 09/04/2020.
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public struct CPU_Load: value_t, Codable {
    var totalUsage: Double = 0
    var usagePerCore: [Double] = []
    var usageECores: Double? = nil
    var usagePCores: Double? = nil
    
    var systemLoad: Double = 0
    var userLoad: Double = 0
    var idleLoad: Double = 0
    
    public var widgetValue: Double {
        get {
            return self.totalUsage
        }
    }
}

public struct CPU_Limit: Codable {
    var scheduler: Int = 0
    var cpus: Int = 0
    var speed: Int = 0
}

public class CPU: Module {
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications
    
    private var loadReader: LoadReader? = nil
    private var processReader: ProcessReader? = nil
    private var temperatureReader: TemperatureReader? = nil
    private var frequencyReader: FrequencyReader? = nil
    private var limitReader: LimitReader? = nil
    private var averageReader: AverageReader? = nil
    
    private var usagePerCoreState: Bool {
        Store.shared.bool(key: "\(self.config.name)_usagePerCore", defaultValue: false)
    }
    private var splitValueState: Bool {
        Store.shared.bool(key: "\(self.config.name)_splitValue", defaultValue: false)
    }
    private var groupByClustersState: Bool {
        Store.shared.bool(key: "\(self.config.name)_clustersGroup", defaultValue: false)
    }
    private var systemColor: NSColor {
        let color = Color.secondRed
        let key = Store.shared.string(key: "\(self.config.name)_systemColor", defaultValue: color.key)
        if let c = Color.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var userColor: NSColor {
        let color = Color.secondBlue
        let key = Store.shared.string(key: "\(self.config.name)_userColor", defaultValue: color.key)
        if let c = Color.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    
    private var eCoreColor: NSColor {
        let color = Color.teal
        let key = Store.shared.string(key: "\(self.config.name)_eCoresColor", defaultValue: color.key)
        if let c = Color.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var pCoreColor: NSColor {
        let color = Color.secondBlue
        let key = Store.shared.string(key: "\(self.config.name)_pCoresColor", defaultValue: color.key)
        if let c = Color.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    
    public init() {
        self.settingsView = Settings("CPU")
        self.popupView = Popup("CPU")
        self.portalView = Portal("CPU")
        self.notificationsView = Notifications(.CPU)
        
        super.init(
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView
        )
        guard self.available else { return }
        
        self.loadReader = LoadReader(.CPU)
        self.processReader = ProcessReader(.CPU)
        self.averageReader = AverageReader(.CPU, popup: true)
        self.temperatureReader = TemperatureReader(.CPU, popup: true)
        
        #if arch(x86_64)
        self.limitReader = LimitReader(.CPU, popup: true)
        self.frequencyReader = FrequencyReader(.CPU, popup: true)
        #endif
        
        self.settingsView.callback = { [weak self] in
            self?.loadReader?.read()
        }
        self.settingsView.callbackWhenUpdateNumberOfProcesses = {
            self.popupView.numberOfProcessesUpdated()
            DispatchQueue.global(qos: .background).async {
                self.processReader?.read()
            }
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.loadReader?.setInterval(value)
        }
        self.settingsView.setTopInterval = { [weak self] value in
            self?.processReader?.setInterval(value)
        }
        self.settingsView.IPGCallback = { [weak self] value in
            if value {
                self?.frequencyReader?.setup()
            }
            self?.popupView.toggleFrequency(state: value)
        }
        
        self.loadReader?.callbackHandler = { [weak self] value in
            self?.loadCallback(value)
        }
        self.loadReader?.readyCallback = { [weak self] in
            self?.readyHandler()
        }
        
        self.processReader?.callbackHandler = { [weak self] value in
            if let list = value {
                self?.popupView.processCallback(list)
            }
        }
        
        self.temperatureReader?.callbackHandler = { [weak self] value in
            if let v = value  {
                self?.popupView.temperatureCallback(v)
            }
        }
        self.frequencyReader?.callbackHandler = { [weak self] value in
            if let v = value  {
                self?.popupView.frequencyCallback(v)
            }
        }
        self.limitReader?.callbackHandler = { [weak self] value in
            if let v = value  {
                self?.popupView.limitCallback(v)
            }
        }
        self.averageReader?.callbackHandler = { [weak self] value in
            if let v = value  {
                self?.popupView.averageCallback(v)
            }
        }
        
        if let reader = self.loadReader {
            self.addReader(reader)
        }
        if let reader = self.processReader {
            self.addReader(reader)
        }
        if let reader = self.temperatureReader {
            self.addReader(reader)
        }
        if let reader = self.frequencyReader {
            self.addReader(reader)
        }
        if let reader = self.limitReader {
            self.addReader(reader)
        }
        if let reader = self.averageReader {
            self.addReader(reader)
        }
    }
    
    private func loadCallback(_ raw: CPU_Load?) {
        guard let value = raw, self.enabled else { return }
        
        self.popupView.loadCallback(value)
        self.portalView.loadCallback(value)
        self.notificationsView.loadCallback(value)
        
        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: Widget) in
            switch w.item {
            case let widget as Mini: widget.setValue(value.totalUsage)
            case let widget as LineChart: widget.setValue(value.totalUsage)
            case let widget as BarChart:
                var val: [[ColorValue]] = [[ColorValue(value.totalUsage)]]
                let cores = SystemKit.shared.device.info.cpu?.cores ?? []
                
                if self.usagePerCoreState {
                    if widget.colorState == .cluster {
                        val = []
                        for (i, v) in value.usagePerCore.enumerated() {
                            let core = cores.first(where: {$0.id == i })
                            val.append([ColorValue(v, color: core?.type == .efficiency ? self.eCoreColor : self.pCoreColor)])
                        }
                    } else {
                        val = value.usagePerCore.map({ [ColorValue($0)] })
                    }
                } else if self.splitValueState {
                    val = [[
                        ColorValue(value.systemLoad, color: self.systemColor),
                        ColorValue(value.userLoad, color: self.userColor)
                    ]]
                } else if self.groupByClustersState, let e = value.usageECores, let p = value.usagePCores {
                    if widget.colorState == .cluster {
                        val = [
                            [ColorValue(e, color: self.eCoreColor)],
                            [ColorValue(p, color: self.pCoreColor)]
                        ]
                    } else {
                        val = [[ColorValue(e)], [ColorValue(p)]]
                    }
                }
                widget.setValue(val)
            case let widget as PieChart:
                widget.setValue([
                    circle_segment(value: value.systemLoad, color: self.systemColor),
                    circle_segment(value: value.userLoad, color: self.userColor)
                ])
            case let widget as Tachometer:
                widget.setValue([
                    circle_segment(value: value.systemLoad, color: self.systemColor),
                    circle_segment(value: value.userLoad, color: self.userColor)
                ])
            default: break
            }
        }
    }
}
