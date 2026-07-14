import UIKit

class ViewController: UIViewController {

    private let label: UILabel = {
        let label = UILabel()
        label.text = "Hello, iOS!"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitle: UILabel = {
        let label = UILabel()
        label.text = "UIKit Hello World Demo"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let button: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("点我计数", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var count = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "首页"

        view.addSubview(label)
        view.addSubview(subtitle)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 120),

            subtitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),

            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 40),
            button.widthAnchor.constraint(equalToConstant: 160),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    }

    @objc private func buttonTapped() {
        count += 1
        label.text = "点击了 \(count) 次"
    }
}
