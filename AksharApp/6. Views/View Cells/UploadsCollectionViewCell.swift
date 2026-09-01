import UIKit

class UploadsCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var containerView: UIView!
    
    var representedDocId: String?
    private let selectionCircle = UIImageView()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .left
        titleLabel.adjustsFontSizeToFitWidth = false
        
        selectionCircle.backgroundColor = .systemBackground
        selectionCircle.layer.cornerRadius = 14
        selectionCircle.clipsToBounds = true

        selectionCircle.translatesAutoresizingMaskIntoConstraints = false
        selectionCircle.image = UIImage(systemName: "circle")
        selectionCircle.tintColor = .systemGray3
        selectionCircle.isHidden = true

        imageView.addSubview(selectionCircle)

        NSLayoutConstraint.activate([
            selectionCircle.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -6),
            selectionCircle.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            selectionCircle.widthAnchor.constraint(equalToConstant: 28),
            selectionCircle.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()

        selectionCircle.isHidden = true
        selectionCircle.image = UIImage(systemName: "circle")

        representedDocId = nil
        imageView.image = nil
        titleLabel.text = nil
        dateLabel.text = nil

        imageView.layer.borderWidth = 0
        imageView.layer.borderColor = nil
        imageView.backgroundColor = .clear
    }
    
    func updateSelectionUI(isSelecting: Bool, isSelected: Bool) {

        if isSelecting {

            selectionCircle.isHidden = false

            if isSelected {
                selectionCircle.image = UIImage(systemName: "checkmark.circle.fill")
                selectionCircle.tintColor = .systemBlue
            } else {
                selectionCircle.image = UIImage(systemName: "circle")
                selectionCircle.tintColor = .systemGray3
            }

        } else {
            selectionCircle.isHidden = true
        }
    }
    
    func configure(title: String, dateText: String, image: UIImage?) {
        titleLabel.text = title
        dateLabel.text = dateText
        imageView.image = image
    }
}
