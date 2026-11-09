import SwiftUI
import UIKit

/// An iOS Timer-style picker: an hours wheel and a minutes wheel (5-minute steps),
/// with fixed "hours" / "min" labels beside the selected row.
struct DurationWheelPicker: UIViewRepresentable {
    @Binding var hours: Int
    @Binding var minutes: Int
    var maxHours: Int = 23

    static let minuteSteps: [Int] = Array(stride(from: 0, through: 55, by: 5))

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DurationPickerView {
        let view = DurationPickerView()
        view.picker.dataSource = context.coordinator
        view.picker.delegate = context.coordinator
        view.picker.selectRow(clampedHours, inComponent: 0, animated: false)
        view.picker.selectRow(minuteRow, inComponent: 1, animated: false)
        view.setHourLabel(singular: clampedHours == 1)
        return view
    }

    func updateUIView(_ view: DurationPickerView, context: Context) {
        context.coordinator.parent = self
        if view.picker.selectedRow(inComponent: 0) != clampedHours {
            view.picker.selectRow(clampedHours, inComponent: 0, animated: true)
        }
        if view.picker.selectedRow(inComponent: 1) != minuteRow {
            view.picker.selectRow(minuteRow, inComponent: 1, animated: true)
        }
        view.setHourLabel(singular: clampedHours == 1)
    }

    private var clampedHours: Int { min(max(hours, 0), maxHours) }
    private var minuteRow: Int { min(max(minutes / 5, 0), Self.minuteSteps.count - 1) }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: DurationWheelPicker

        init(_ parent: DurationWheelPicker) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? parent.maxHours + 1 : DurationWheelPicker.minuteSteps.count
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            DurationPickerView.componentWidth(for: pickerView.bounds.width)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 36 }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let width = DurationPickerView.componentWidth(for: pickerView.bounds.width)
            let container = view ?? UIView()
            container.frame = CGRect(x: 0, y: 0, width: width, height: 36)

            let label: UILabel
            if let existing = container.viewWithTag(42) as? UILabel {
                label = existing
            } else {
                label = UILabel()
                label.tag = 42
                label.textAlignment = .right
                label.font = DurationPickerView.numberFont
                container.addSubview(label)
            }
            label.frame = CGRect(x: 0, y: 0, width: width * DurationPickerView.numberEdge, height: 36)
            let value = component == 0 ? row : DurationWheelPicker.minuteSteps[row]
            label.text = "\(value)"
            return container
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            if component == 0 {
                parent.hours = row
            } else {
                parent.minutes = DurationWheelPicker.minuteSteps[row]
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

/// Hosts the UIPickerView plus the stationary unit labels.
final class DurationPickerView: UIView {
    let picker = UIPickerView()
    private let hourLabel = UILabel()
    private let minuteLabel = UILabel()
    private var lastWidth: CGFloat = 0

    /// Fraction of a component's width at which the number's right edge sits.
    static let numberEdge: CGFloat = 0.45
    static let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 23, weight: .regular)
    static let gutter: CGFloat = 24

    static func componentWidth(for totalWidth: CGFloat) -> CGFloat {
        max((totalWidth - gutter) / 2, 60)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(picker)
        for label in [hourLabel, minuteLabel] {
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.textColor = .label
            label.isUserInteractionEnabled = false
            addSubview(label)
        }
        hourLabel.text = "hours"
        minuteLabel.text = "min"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setHourLabel(singular: Bool) {
        let text = singular ? "hour" : "hours"
        if hourLabel.text != text {
            hourLabel.text = text
            setNeedsLayout()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 216)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            picker.reloadAllComponents()
        }

        let w = Self.componentWidth(for: bounds.width)
        let spacing: CGFloat = 5 // UIPickerView's approximate inter-component spacing
        let origin0 = (bounds.width - (2 * w + spacing)) / 2
        let origin1 = origin0 + w + spacing
        let midY = bounds.midY

        for (label, origin) in [(hourLabel, origin0), (minuteLabel, origin1)] {
            label.sizeToFit()
            let x = origin + w * Self.numberEdge + 8
            label.frame = CGRect(x: x, y: midY - label.bounds.height / 2,
                                 width: label.bounds.width, height: label.bounds.height)
        }
        bringSubviewToFront(hourLabel)
        bringSubviewToFront(minuteLabel)
    }
}
