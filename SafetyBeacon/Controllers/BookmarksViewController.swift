//
//  BookmarksViewController.swift
//  SafetyBeacon
//
//  Created by Nathan Tannar on 9/25/17.
//  Last modified by Jason Tsang on 10/29/2017
//  Copyright © 2017 Nathan Tannar. All rights reserved.
//

import CoreLocation
import AddressBookUI
import NTComponents
import Parse
import UIKit

class BookmarksViewController: UITableViewController {

    // MARK: - Properties
    
    var bookmarks = [PFObject]()
    
    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bookmarks"
    }
    
    func refreshSafeZones() {
        
        // query db
        tableView.reloadData()
        
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = NTTableViewHeaderFooterView()
        if section == 0 {
            header.textLabel.text = "Add Bookmarks"
        } else if section == 1 {
            header.textLabel.text = "Existing Bookmarks"
        }
        return header
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        }
        return bookmarks.count
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 44
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return indexPath.section <= 1 ? 80 : UITableViewAutomaticDimension
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        
        if indexPath.section == 0  {
            cell.textLabel?.text = "+"
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        
        cell.textLabel?.text = bookmarks[indexPath.row]["name"] as? String
        //        cell.detailTextLabel?.text = safeZones[indexPath.row]["name"] as? String
        return cell
        
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            addBookmark()
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section != 0
    }
    
//    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
//        let action = UITableViewRowAction(style: UITableViewRowActionStyle.destructive, title: "Delete") { (action, indexPath) in
//            self.bookmarks[indexPath.row].deleteInBackground(block: { (success, error) in
//                guard success else {
//                    return
//                }
//                self.bookmarks.remove(at: indexPath.row)
//                tableView.deleteRows(at: [indexPath], with: .fade)
//            })
//            return
//        }
//    }
    
    // MARK: - User Actions
    func getCoordinates(address: String, completion: @escaping (CLLocationCoordinate2D?)->Void) {
        CLGeocoder().geocodeAddressString(address, completionHandler: { (placemarks, error) in
            
            if error != nil {
                print(error as Any)
                return
            }
            if placemarks?.count != nil {
                let placemark = placemarks?[0]
                let location = placemark?.location
                let coordinate = location?.coordinate
                print("\nlat: \(coordinate!.latitude), long: \(coordinate!.longitude)")
                if placemark?.areasOfInterest?.count != nil {
                    let areaOfInterest = placemark!.areasOfInterest![0]
                    print(areaOfInterest)
                    completion(coordinate)
                } else {
                    print("No area of interest found.")
                    completion(nil)
                }
            }
            
        })
    }

    func addBookmark() {
        let alertController = UIAlertController(title: "Add Bookmark", message: "Input Bookmark name and address below:", preferredStyle: UIAlertControllerStyle.alert)
        
        let addAction = UIAlertAction(title: "Add", style: UIAlertActionStyle.default) { (alertAction: UIAlertAction!) -> Void in
            let nameField = alertController.textFields![0] as UITextField
            let streetField = alertController.textFields![1] as UITextField
            let cityField = alertController.textFields![2] as UITextField
            let provinceField = alertController.textFields![3] as UITextField
            let postalField = alertController.textFields![4] as UITextField

            print("\(nameField.text ?? "Nothing entered")")
            print("\(streetField.text ?? "Noting entered")")
            print("\(cityField.text ?? "Noting entered")")
            print("\(provinceField.text ?? "Noting entered")")
            print("\(postalField.text ?? "Noting entered")")
            
            let address = "\(streetField.text ?? "Null"), \(cityField.text ?? "Null"), \(provinceField.text ?? "Null"), \(postalField.text ?? "Null")"
            print ("\(address)")
            
            self.getCoordinates(address: address, completion: { (coordinate) in
                guard let coordinate = coordinate else {
                    // handle error
                    return
                }
                self.saveBookmark(name: nameField.text!, addressLatitude: coordinate.latitude, addressLongitude: coordinate.longitude)
            })
        }
//        addAction.isEnabled = false
        
        alertController.addTextField { nameField in nameField.placeholder = "Bookmark Name" }
        alertController.addTextField { streetField in streetField.placeholder = "Street Address" }
        alertController.addTextField { cityField in cityField.placeholder = "City" }
        alertController.addTextField { provinceField in provinceField.placeholder = "Province/ Territory" }
        alertController.addTextField { postalField in postalField.placeholder = "Postal Code" }

        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil)
        alertController.addAction(addAction)
        alertController.addAction(cancelAction)
        present(alertController, animated: true, completion: nil)
        
    }
    
    func saveBookmark(name: String, addressLatitude: Double, addressLongitude: Double) {
        guard let currentUser = User.current(), currentUser.isCaretaker, let patient = currentUser.patient else { return }
        
        let bookmark = PFObject(className: "Bookmarks")
        bookmark["long"] = addressLatitude
        bookmark["lat"] = addressLongitude
        bookmark["name"] = "Test"
        bookmark["patient"] = patient
        bookmark.saveInBackground { (success, error) in
            guard success else {
                // handle error
                Log.write(.error, error.debugDescription)
                NTPing(type: .isDanger, title: error?.localizedDescription).show(duration: 3)
                return
            }
            NTPing(type: .isSuccess, title: "Bookmark successfully saved").show(duration: 3)
        }
    }
}
